import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../core/crypto/crypto_service.dart';

/// Base local SQLCipher (AES-256, páginas cifradas) con búsqueda de texto
/// completo FTS5 insensible a acentos y mayúsculas. Todo ocurre en el equipo:
/// buscar es instantáneo y funciona sin internet.
class ErgosDatabase {
  ErgosDatabase._(this.db);
  final Database db;

  static Future<ErgosDatabase> open(Uint8List dbKey) async {
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'ergos.db');
    final db = sqlite3.open(path);
    // Llave cruda (hex) -> sin KDF adicional; ya viene de Argon2id + HKDF.
    db.execute('''PRAGMA key = "x'${CryptoService.hex(dbKey)}'";''');
    try {
      db.select('SELECT count(*) FROM sqlite_master'); // falla si la llave es incorrecta
    } on SqliteException {
      db.dispose();
      throw StateError('No se pudo abrir la base: llave incorrecta o archivo dañado');
    }
    db.execute('PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA secure_delete = ON;');
    final d = ErgosDatabase._(db);
    d._migrate();
    return d;
  }

  void close() => db.dispose();

  void _migrate() {
    final v = db.select('PRAGMA user_version').first.values.first as int;
    if (v < 1) {
      db.execute(_schemaV1);
      db.execute('PRAGMA user_version = 1');
    }
  }

  static const _schemaV1 = '''
CREATE TABLE person(
  id TEXT PRIMARY KEY,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  birth_date TEXT,                 -- ISO yyyy-MM-dd; la edad se calcula
  phone TEXT, email TEXT, occupation TEXT, marital_status TEXT, household TEXT,
  god_relation TEXT,               -- relación actual con Dios
  spiritual_state TEXT,            -- etapa de fe, práctica, comunidad
  personal_battles TEXT,           -- batallas personales
  environment TEXT,                -- familia, trabajo, entorno
  mental_notes TEXT,               -- variables emocionales / mentales
  strengths TEXT,
  consent_status TEXT NOT NULL DEFAULT 'pendiente', -- pendiente | firmado | revocado
  consent_at INTEGER,
  updated_at INTEGER NOT NULL,     -- ms epoch UTC (reloj de sincronización)
  deleted INTEGER NOT NULL DEFAULT 0,
  dirty INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE memory(
  id TEXT PRIMARY KEY,
  person_id TEXT NOT NULL REFERENCES person(id),
  occurred_at INTEGER NOT NULL,
  kind TEXT NOT NULL DEFAULT 'sesion', -- sesion | discipulado | liderazgo | ministerio | evento | oracion
  title TEXT NOT NULL,
  summary TEXT, body TEXT,
  god_relation TEXT, emotional_state TEXT, battles TEXT, environment TEXT,
  prayer_points TEXT, agreements TEXT, next_steps TEXT,
  follow_up_at INTEGER,
  tags TEXT,                        -- separadas por espacios
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  dirty INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX memory_person ON memory(person_id, occurred_at DESC);
CREATE INDEX memory_follow ON memory(follow_up_at) WHERE follow_up_at IS NOT NULL AND deleted = 0;

-- vínculos: cónyuge, hijo, hermano, líder... (reutiliza la idea de la Memoria de Iglesia)
CREATE TABLE person_link(
  person_id TEXT NOT NULL, other_id TEXT NOT NULL, relation TEXT NOT NULL,
  PRIMARY KEY(person_id, other_id, relation)
);

-- id local <-> archivo remoto en Drive
CREATE TABLE remote_file(
  kind TEXT NOT NULL, local_id TEXT NOT NULL, file_id TEXT NOT NULL, remote_updated INTEGER NOT NULL,
  PRIMARY KEY(kind, local_id)
);
CREATE TABLE kv(key TEXT PRIMARY KEY, value TEXT);

CREATE VIRTUAL TABLE memory_fts USING fts5(
  title, summary, body, god_relation, emotional_state, battles, environment,
  prayer_points, agreements, next_steps, tags,
  content='memory', content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 2'
);
CREATE TRIGGER memory_ai AFTER INSERT ON memory BEGIN
  INSERT INTO memory_fts(rowid,title,summary,body,god_relation,emotional_state,battles,environment,prayer_points,agreements,next_steps,tags)
  VALUES (new.rowid,new.title,new.summary,new.body,new.god_relation,new.emotional_state,new.battles,new.environment,new.prayer_points,new.agreements,new.next_steps,new.tags);
END;
CREATE TRIGGER memory_ad AFTER DELETE ON memory BEGIN
  INSERT INTO memory_fts(memory_fts,rowid,title,summary,body,god_relation,emotional_state,battles,environment,prayer_points,agreements,next_steps,tags)
  VALUES ('delete',old.rowid,old.title,old.summary,old.body,old.god_relation,old.emotional_state,old.battles,old.environment,old.prayer_points,old.agreements,old.next_steps,old.tags);
END;
CREATE TRIGGER memory_au AFTER UPDATE ON memory BEGIN
  INSERT INTO memory_fts(memory_fts,rowid,title,summary,body,god_relation,emotional_state,battles,environment,prayer_points,agreements,next_steps,tags)
  VALUES ('delete',old.rowid,old.title,old.summary,old.body,old.god_relation,old.emotional_state,old.battles,old.environment,old.prayer_points,old.agreements,old.next_steps,old.tags);
  INSERT INTO memory_fts(rowid,title,summary,body,god_relation,emotional_state,battles,environment,prayer_points,agreements,next_steps,tags)
  VALUES (new.rowid,new.title,new.summary,new.body,new.god_relation,new.emotional_state,new.battles,new.environment,new.prayer_points,new.agreements,new.next_steps,new.tags);
END;

CREATE VIRTUAL TABLE person_fts USING fts5(
  first_name, last_name, occupation, god_relation, spiritual_state, personal_battles, environment, mental_notes,
  content='person', content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 2'
);
CREATE TRIGGER person_ai AFTER INSERT ON person BEGIN
  INSERT INTO person_fts(rowid,first_name,last_name,occupation,god_relation,spiritual_state,personal_battles,environment,mental_notes)
  VALUES (new.rowid,new.first_name,new.last_name,new.occupation,new.god_relation,new.spiritual_state,new.personal_battles,new.environment,new.mental_notes);
END;
CREATE TRIGGER person_au AFTER UPDATE ON person BEGIN
  INSERT INTO person_fts(person_fts,rowid,first_name,last_name,occupation,god_relation,spiritual_state,personal_battles,environment,mental_notes)
  VALUES ('delete',old.rowid,old.first_name,old.last_name,old.occupation,old.god_relation,old.spiritual_state,old.personal_battles,old.environment,old.mental_notes);
  INSERT INTO person_fts(rowid,first_name,last_name,occupation,god_relation,spiritual_state,personal_battles,environment,mental_notes)
  VALUES (new.rowid,new.first_name,new.last_name,new.occupation,new.god_relation,new.spiritual_state,new.personal_battles,new.environment,new.mental_notes);
END;
''';
}
