import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/crypto/crypto_service.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/sync/drive_sync_service.dart';

/// Texto del contrato versionado + evidencia: hash SHA-256 del texto exacto que
/// la persona leyó, fecha UTC, firma manuscrita y video de consentimiento verbal.
class ConsentService {
  ConsentService({required this.crypto, required this.repo, required this.blobKey, this.drive});
  final CryptoService crypto;
  final Repository repo;
  final Uint8List blobKey;
  final DriveSyncService? drive;

  static const version = 'v1';

  static String sha256Hex(String text) => hash.sha256.convert(utf8.encode(text)).toString();

  /// La librería pdf usa fuentes Latin-1: acentos y ñ funcionan; se normalizan
  /// signos tipográficos fuera de Latin-1.
  static String _latin1(String s) => s
      .replaceAll(RegExp('[“”]'), '"')
      .replaceAll(RegExp('[‘’]'), "'")
      .replaceAll(RegExp('[–—]'), '-')
      .replaceAll('…', '...')
      .replaceAll('•', '-')
      .replaceAll('☐', '[ ]')
      .replaceAll('☑', '[x]');

  Future<Uint8List> buildPdf({
    required Person person,
    required String contractText,
    required Map<String, bool> accepted,
    required Uint8List signaturePng,
    required bool hasVideo,
    String? guardianName,
  }) async {
    final doc = pw.Document(title: 'Consentimiento Ergos - ${person.fullName}', author: 'Ergos');
    final when = DateTime.now().toUtc();
    final h = sha256Hex(contractText);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => [
        pw.Header(level: 0, text: 'Consentimiento informado y autorización de tratamiento de datos'),
        for (final para in _latin1(contractText).split(RegExp(r'\n{2,}')))
          pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: pw.Text(para.replaceAll(RegExp(r'[#*]'), '').trim(), style: const pw.TextStyle(fontSize: 9.5))),
        pw.Divider(),
        pw.Text('Autorizaciones otorgadas:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        for (final e in accepted.entries) pw.Text('${e.value ? "[x]" : "[ ]"} ${_latin1(e.key)}', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 14),
        pw.Text('Titular: ${person.fullName}'),
        if (guardianName != null) pw.Text('Representante legal: $guardianName'),
        pw.Text('Fecha y hora (UTC): ${when.toIso8601String()}'),
        pw.Text('Video de consentimiento verbal: ${hasVideo ? "si, almacenado cifrado" : "no"}'),
        pw.SizedBox(height: 10),
        pw.Container(height: 90, width: 220, child: pw.Image(pw.MemoryImage(signaturePng))),
        pw.Text('Firma', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 8),
        pw.Text('Huella digital del texto aceptado (SHA-256, version $version):\n$h', style: const pw.TextStyle(fontSize: 8)),
      ],
    ));
    return doc.save();
  }

  /// Cifra y guarda localmente (bandeja de salida); sube a Drive si hay sesión.
  Future<void> store({
    required String personId,
    required Uint8List pdf,
    required Uint8List signaturePng,
    File? plainVideo,
  }) async {
    final dir = await getApplicationSupportDirectory();
    final out = Directory(p.join(dir.path, 'consent_outbox', personId))..createSync(recursive: true);
    final encPdf = await crypto.encryptBytes(pdf, blobKey, aad: utf8.encode('consent/$personId/pdf'));
    final encSig = await crypto.encryptBytes(signaturePng, blobKey, aad: utf8.encode('consent/$personId/sig'));
    File(p.join(out.path, 'consentimiento_$version.pdf.erg')).writeAsBytesSync(encPdf);
    File(p.join(out.path, 'firma_$version.png.erg')).writeAsBytesSync(encSig);
    if (plainVideo != null) {
      await crypto.encryptFile(plainVideo, File(p.join(out.path, 'video_$version.ergv')), blobKey);
      await crypto.shred(plainVideo); // el video en claro no se conserva
    }
    repo.setConsent(personId, 'firmado');
    await flushOutbox();
  }

  /// Sube lo pendiente y borra la copia local solo si la subida tuvo éxito.
  Future<void> flushOutbox() async {
    final d = drive;
    if (d == null) return;
    final dir = await getApplicationSupportDirectory();
    final root = Directory(p.join(dir.path, 'consent_outbox'));
    if (!root.existsSync()) return;
    for (final personDir in root.listSync().whereType<Directory>()) {
      final id = p.basename(personDir.path);
      final pdf = File(p.join(personDir.path, 'consentimiento_$version.pdf.erg'));
      final sig = File(p.join(personDir.path, 'firma_$version.png.erg'));
      final vid = File(p.join(personDir.path, 'video_$version.ergv'));
      if (!pdf.existsSync() || !sig.existsSync()) continue;
      try {
        await d.uploadConsentArtifacts(
          personId: id,
          encryptedPdf: pdf.readAsBytesSync(),
          encryptedSignature: sig.readAsBytesSync(),
          encryptedVideo: vid.existsSync() ? vid : null,
          version: version,
        );
        personDir.deleteSync(recursive: true);
      } catch (_) {/* se reintenta en la próxima sincronización */}
    }
  }
}
