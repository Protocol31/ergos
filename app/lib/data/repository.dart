import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'db/database.dart';
import 'models.dart';

class Stats {
  Stats(this.people, this.memories, this.pendingConsent, this.followUps);
  final int people, memories, pendingConsent, followUps;
}

class Repository {
  Repository(this._d);
  final ErgosDatabase _d;
  Database get _db => _d.db;
  static const _uuid = Uuid();

  String newId() => _uuid.v4();

  // ------------------------------------------------------------- personas
  void savePerson(Person p) {
    p.updatedAt = nowMs();
    final m = p.toMap();
    final cols = m.keys.toList();
    _db.execute(
      'INSERT INTO person(${cols.join(',')},dirty) VALUES(${List.filled(cols.length, '?').join(',')},1) '
      'ON CONFLICT(id) DO UPDATE SET ${cols.where((c) => c != 'id').map((c) => '$c=excluded.$c').join(',')},dirty=1',
      m.values.toList(),
    );
  }

  Person? person(String id) {
    final r = _db.select('SELECT * FROM person WHERE id=?', [id]);
    return r.isEmpty ? null : Person.fromMap(r.first);
  }

  List<Person> people({String? filter}) {
    final r = filter == null || filter.trim().isEmpty
        ? _db.select('SELECT * FROM person WHERE deleted=0 ORDER BY last_name COLLATE NOCASE, first_name COLLATE NOCASE')
        : _db.select(
            'SELECT p.* FROM person p JOIN person_fts f ON f.rowid=p.rowid WHERE person_fts MATCH ? AND p.deleted=0 ORDER BY rank',
            [_ftsQuery(filter)]);
    return r.map(Person.fromMap).toList();
  }

  /// Borrado lógico (tombstone) para que la eliminación también se sincronice.
  void deletePerson(String id) {
    final now = nowMs();
    _db.execute('UPDATE person SET deleted=1,dirty=1,updated_at=? WHERE id=?', [now, id]);
    _db.execute('UPDATE memory SET deleted=1,dirty=1,updated_at=? WHERE person_id=?', [now, id]);
  }

  void setConsent(String personId, String status) {
    _db.execute(
        'UPDATE person SET consent_status=?,consent_at=?,dirty=1,updated_at=? WHERE id=?',
        [status, nowMs(), nowMs(), personId]);
  }

  // ------------------------------------------------------------- memorias
  void saveMemory(Memory m) {
    m.updatedAt = nowMs();
    final map = m.toMap();
    final cols = map.keys.toList();
    _db.execute(
      'INSERT INTO memory(${cols.join(',')},dirty) VALUES(${List.filled(cols.length, '?').join(',')},1) '
      'ON CONFLICT(id) DO UPDATE SET ${cols.where((c) => c != 'id').map((c) => '$c=excluded.$c').join(',')},dirty=1',
      map.values.toList(),
    );
  }

  List<Memory> memoriesOf(String personId) => _db
      .select('SELECT * FROM memory WHERE person_id=? AND deleted=0 ORDER BY occurred_at DESC', [personId])
      .map(Memory.fromMap)
      .toList();

  List<Memory> recentMemories({int limit = 8}) => _db
      .select('SELECT * FROM memory WHERE deleted=0 ORDER BY occurred_at DESC LIMIT ?', [limit])
      .map(Memory.fromMap)
      .toList();

  List<Memory> followUps({int days = 14}) {
    final until = DateTime.now().add(Duration(days: days)).toUtc().millisecondsSinceEpoch;
    return _db
        .select('SELECT * FROM memory WHERE deleted=0 AND follow_up_at IS NOT NULL AND follow_up_at<=? ORDER BY follow_up_at', [until])
        .map(Memory.fromMap)
        .toList();
  }

  void deleteMemory(String id) =>
      _db.execute('UPDATE memory SET deleted=1,dirty=1,updated_at=? WHERE id=?', [nowMs(), id]);

  // --------------------------------------------------------------- búsqueda
  /// Consulta natural -> FTS5: cada palabra con prefijo ("ansied" encuentra
  /// "ansiedad"), sin acentos, ordenada por relevancia BM25.
  String _ftsQuery(String q) {
    final terms = q
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), ''))
        .where((t) => t.isNotEmpty)
        .map((t) => '"$t"*');
    return terms.join(' ');
  }

  List<SearchHit> search(String q, {int limit = 40}) {
    final fts = _ftsQuery(q);
    if (fts.isEmpty) return [];
    final hits = <SearchHit>[];
    final mem = _db.select('''
      SELECT m.id, m.person_id, m.title, m.occurred_at,
             snippet(memory_fts, -1, '«', '»', ' … ', 14) AS snip,
             p.first_name || ' ' || p.last_name AS pname
      FROM memory_fts JOIN memory m ON m.rowid = memory_fts.rowid
      JOIN person p ON p.id = m.person_id
      WHERE memory_fts MATCH ? AND m.deleted=0 AND p.deleted=0
      ORDER BY rank LIMIT ?''', [fts, limit]);
    for (final r in mem) {
      hits.add(SearchHit(kind: 'memory', id: r['id'], personId: r['person_id'], personName: r['pname'], title: r['title'], snippet: r['snip'] ?? '', when: r['occurred_at']));
    }
    final per = _db.select('''
      SELECT p.id, p.first_name || ' ' || p.last_name AS pname,
             snippet(person_fts, -1, '«', '»', ' … ', 12) AS snip
      FROM person_fts JOIN person p ON p.rowid = person_fts.rowid
      WHERE person_fts MATCH ? AND p.deleted=0 ORDER BY rank LIMIT ?''', [fts, limit]);
    for (final r in per) {
      hits.insert(0, SearchHit(kind: 'person', id: r['id'], personId: r['id'], personName: r['pname'], title: r['pname'], snippet: r['snip'] ?? '', when: null));
    }
    return hits;
  }

  Stats stats() {
    int one(String sql) => _db.select(sql).first.values.first as int;
    return Stats(
      one('SELECT count(*) FROM person WHERE deleted=0'),
      one('SELECT count(*) FROM memory WHERE deleted=0'),
      one("SELECT count(*) FROM person WHERE deleted=0 AND consent_status!='firmado'"),
      followUps().length,
    );
  }

  // ------------------------------------------------- soporte para sincronizar
  List<Map<String, Object?>> dirtyRows(String table) =>
      _db.select('SELECT * FROM $table WHERE dirty=1').map((r) => Map<String, Object?>.from(r)).toList();

  void markClean(String table, String id) =>
      _db.execute('UPDATE $table SET dirty=0 WHERE id=?', [id]);

  /// Aplica un registro remoto (last-writer-wins por updated_at).
  /// Devuelve true si cambió algo local.
  bool applyRemote(String table, Map<String, Object?> m) {
    final cur = _db.select('SELECT updated_at FROM $table WHERE id=?', [m['id']]);
    if (cur.isNotEmpty && (cur.first['updated_at'] as int) >= (m['updated_at'] as int)) return false;
    final cols = m.keys.toList();
    _db.execute(
      'INSERT INTO $table(${cols.join(',')},dirty) VALUES(${List.filled(cols.length, '?').join(',')},0) '
      'ON CONFLICT(id) DO UPDATE SET ${cols.where((c) => c != 'id').map((c) => '$c=excluded.$c').join(',')},dirty=0',
      m.values.toList(),
    );
    return true;
  }

  ({String fileId, int remoteUpdated})? remoteFile(String kind, String id) {
    final r = _db.select('SELECT file_id,remote_updated FROM remote_file WHERE kind=? AND local_id=?', [kind, id]);
    return r.isEmpty ? null : (fileId: r.first['file_id'] as String, remoteUpdated: r.first['remote_updated'] as int);
  }

  void setRemoteFile(String kind, String id, String fileId, int updated) => _db.execute(
      'INSERT OR REPLACE INTO remote_file(kind,local_id,file_id,remote_updated) VALUES(?,?,?,?)',
      [kind, id, fileId, updated]);

  String? kv(String k) {
    final r = _db.select('SELECT value FROM kv WHERE key=?', [k]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  void setKv(String k, String v) =>
      _db.execute('INSERT OR REPLACE INTO kv(key,value) VALUES(?,?)', [k, v]);
}
