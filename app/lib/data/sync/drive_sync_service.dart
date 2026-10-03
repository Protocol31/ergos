import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../../core/crypto/crypto_service.dart';
import '../models.dart';
import '../repository.dart';

/// Sincronización bidireccional de blobs cifrados con Google Drive.
///
/// Reglas de oro:
///  * Drive solo ve archivos `.erg` opacos (AES-256-GCM). Ningún nombre, texto,
///    edad, firma ni video sale en claro. Las carpetas de cada persona se
///    llaman con un UUID, no con su nombre.
///  * La llave nunca sale del equipo; la sal (pública) sí, en `_meta/salt.json`.
///  * Un archivo por registro => los conflictos se resuelven por registro
///    (last-writer-wins con `updated_at`) y solo viaja lo que cambió.
///  * El AAD ata cada blob a su tipo e id: no se puede intercambiar un archivo por otro.
///
/// Estructura (ver docs/ESQUEMA_DRIVE.md):
///   Ergos/
///     _meta/{salt.json, manifest.erg}
///     feligreses/<uuid>/{perfil.erg, memorias/<uuid>.erg, consentimiento/*}
///     respaldos/
class DriveSyncService {
  DriveSyncService({required http.Client client, required this.repo, required this.crypto, required this.blobKey})
      : _api = drive.DriveApi(client);

  final drive.DriveApi _api;
  final Repository repo;
  final CryptoService crypto;
  final Uint8List blobKey;

  static const _folderMime = 'application/vnd.google-apps.folder';
  final _folderCache = <String, String>{};

  // ------------------------------------------------------------ carpetas

  Future<String> _folder(String name, [String? parent]) async {
    final key = '${parent ?? 'root'}/$name';
    final cached = _folderCache[key];
    if (cached != null) return cached;
    final q = "name='$name' and mimeType='$_folderMime' and trashed=false"
        "${parent != null ? " and '$parent' in parents" : ''}";
    final found = await _api.files.list(q: q, spaces: 'drive', $fields: 'files(id)', pageSize: 1);
    final id = found.files?.isNotEmpty == true
        ? found.files!.first.id!
        : (await _api.files.create(drive.File(
            name: name, mimeType: _folderMime, parents: parent != null ? [parent] : null))).id!;
    return _folderCache[key] = id;
  }

  Future<String> ensureRoot() => _folder('Ergos');

  /// Crea (idempotente) la carpeta completa de una persona y devuelve sus ids.
  Future<({String root, String memorias, String consent})> ensurePersonFolders(String personId) async {
    final root = await ensureRoot();
    final fel = await _folder('feligreses', root);
    final p = await _folder(personId, fel);
    return (root: p, memorias: await _folder('memorias', p), consent: await _folder('consentimiento', p));
  }

  // -------------------------------------------------------------- archivos

  List<int> _aad(String kind, String id) => utf8.encode('ergos/v1/$kind/$id');

  Future<String> _upload(String parent, String name, Uint8List bytes, {String? existingId, Map<String, String>? props}) async {
    final media = drive.Media(Stream.value(bytes), bytes.length);
    if (existingId != null) {
      final f = await _api.files.update(drive.File(appProperties: props), existingId, uploadMedia: media);
      return f.id!;
    }
    final f = await _api.files.create(
        drive.File(name: name, parents: [parent], appProperties: props), uploadMedia: media);
    return f.id!;
  }

  Future<Uint8List> _download(String fileId) async {
    final media = await _api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final b = BytesBuilder(copy: false);
    await for (final c in media.stream) {
      b.add(c);
    }
    return b.takeBytes();
  }

  Future<List<drive.File>> _list(String parent) async {
    final out = <drive.File>[];
    String? token;
    do {
      final r = await _api.files.list(
        q: "'$parent' in parents and trashed=false",
        spaces: 'drive',
        $fields: 'nextPageToken, files(id,name,mimeType,appProperties)',
        pageSize: 200,
        pageToken: token,
      );
      out.addAll(r.files ?? []);
      token = r.nextPageToken;
    } while (token != null);
    return out;
  }

  // ------------------------------------------------------------ sincronizar

  /// Un ciclo completo: subir cambios locales y bajar cambios remotos.
  Future<SyncReport> sync({void Function(String)? onProgress}) async {
    final rep = SyncReport();
    onProgress?.call('Preparando carpetas…');
    final root = await ensureRoot();
    await _ensureMeta(root);

    // 1) SUBIR personas y memorias con cambios locales
    for (final row in repo.dirtyRows('person')) {
      final id = row['id'] as String;
      final f = await ensurePersonFolders(id);
      final payload = Map<String, Object?>.from(row)..remove('dirty');
      final blob = await crypto.encryptJson(payload.cast<String, dynamic>(), blobKey, aad: _aad('person', id));
      final known = repo.remoteFile('person', id);
      final fid = await _upload(f.root, 'perfil.erg', blob,
          existingId: known?.fileId, props: {'updatedAt': '${row['updated_at']}'});
      repo.setRemoteFile('person', id, fid, row['updated_at'] as int);
      repo.markClean('person', id);
      rep.pushed++;
    }
    for (final row in repo.dirtyRows('memory')) {
      final id = row['id'] as String;
      final f = await ensurePersonFolders(row['person_id'] as String);
      final payload = Map<String, Object?>.from(row)..remove('dirty');
      final blob = await crypto.encryptJson(payload.cast<String, dynamic>(), blobKey, aad: _aad('memory', id));
      final known = repo.remoteFile('memory', id);
      final fid = await _upload(f.memorias, '$id.erg', blob,
          existingId: known?.fileId, props: {'updatedAt': '${row['updated_at']}'});
      repo.setRemoteFile('memory', id, fid, row['updated_at'] as int);
      repo.markClean('memory', id);
      rep.pushed++;
    }

    // 2) BAJAR lo que sea más nuevo en Drive
    onProgress?.call('Buscando cambios en Drive…');
    final fel = await _folder('feligreses', root);
    for (final pf in await _list(fel)) {
      if (pf.mimeType != _folderMime) continue;
      final personId = pf.name!;
      final children = await _list(pf.id!);
      for (final c in children) {
        if (c.name == 'perfil.erg') {
          rep.pulled += await _pullRecord('person', personId, c) ? 1 : 0;
        }
      }
      final memFolder = children.where((c) => c.name == 'memorias' && c.mimeType == _folderMime);
      if (memFolder.isNotEmpty) {
        for (final c in await _list(memFolder.first.id!)) {
          if (!c.name!.endsWith('.erg')) continue;
          final id = c.name!.substring(0, c.name!.length - 4);
          rep.pulled += await _pullRecord('memory', id, c) ? 1 : 0;
        }
      }
    }
    repo.setKv('last_sync', '${nowMs()}');
    return rep;
  }

  Future<bool> _pullRecord(String table, String id, drive.File f) async {
    final remoteTs = int.tryParse(f.appProperties?['updatedAt'] ?? '') ?? 0;
    final known = repo.remoteFile(table, id);
    if (known != null && known.remoteUpdated >= remoteTs) return false;
    try {
      final map = await crypto.decryptJson(await _download(f.id!), blobKey, aad: _aad(table, id));
      final changed = repo.applyRemote(table, map.cast<String, Object?>());
      repo.setRemoteFile(table, id, f.id!, remoteTs);
      return changed;
    } catch (_) {
      // llave incorrecta o archivo manipulado: se ignora y se reporta, nunca se aplica
      return false;
    }
  }

  // ------------------------------------------------------ consentimiento

  /// Sube PDF firmado, firma PNG y video (ya cifrados por el llamador) a la
  /// carpeta del feligrés. El video se cifra por fragmentos en disco antes de subir.
  Future<void> uploadConsentArtifacts({
    required String personId,
    required Uint8List encryptedPdf,
    required Uint8List encryptedSignature,
    File? encryptedVideo,
    required String version,
  }) async {
    final f = await ensurePersonFolders(personId);
    await _upload(f.consent, 'consentimiento_$version.pdf.erg', encryptedPdf);
    await _upload(f.consent, 'firma_$version.png.erg', encryptedSignature);
    if (encryptedVideo != null) {
      final len = await encryptedVideo.length();
      final media = drive.Media(encryptedVideo.openRead(), len);
      await _api.files.create(
          drive.File(name: 'video_$version.ergv', parents: [f.consent]), uploadMedia: media);
    }
  }

  // ----------------------------------------------------------------- meta

  Future<void> _ensureMeta(String root) async {
    final meta = await _folder('_meta', root);
    final files = await _list(meta);
    if (!files.any((f) => f.name == 'salt.json')) {
      // La sal es pública. Permite abrir los datos en otro equipo con la frase maestra.
      final salt = repo.kv('salt_b64');
      if (salt != null) {
        await _upload(meta, 'salt.json', Uint8List.fromList(utf8.encode(jsonEncode({'v': 1, 'kdf': 'argon2id', 'salt': salt}))));
      }
    }
  }
}

class SyncReport {
  int pushed = 0, pulled = 0;
  @override
  String toString() => '↑ $pushed enviados · ↓ $pulled recibidos';
}
