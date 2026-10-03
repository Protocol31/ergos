import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Llaves derivadas de la frase maestra. Nunca se escriben a disco ni se suben a Drive.
class DerivedKeys {
  /// Para SQLCipher (base de datos local).
  final Uint8List dbKey;

  /// Para cifrar blobs (.erg) que viajan a Google Drive.
  final Uint8List blobKey;
  const DerivedKeys(this.dbKey, this.blobKey);
}

class CryptoService {
  static const _magicBlob = [0x45, 0x52, 0x47, 0x31]; // "ERG1"
  static const _magicVideo = [0x45, 0x52, 0x47, 0x56]; // "ERGV"
  static const chunkSize = 1024 * 1024; // 1 MiB por fragmento de video

  static final _aes = AesGcm.with256bits();
  // 64 MiB, 3 pasadas, 2 hilos: ~0.5-1 s en un PC/móvil actual.
  static final _argon = Argon2id(
    memory: 65536,
    parallelism: 2,
    iterations: 3,
    hashLength: 32,
  );
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  Uint8List randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  /// Frase maestra + sal pública -> llaves independientes (separación de dominios con HKDF).
  Future<DerivedKeys> derive(String passphrase, Uint8List salt) async {
    final master = await _argon.deriveKeyFromPassword(
      password: passphrase.trim().replaceAll(RegExp(r'\s+'), ' '),
      nonce: salt,
    );
    Future<Uint8List> sub(String info) async {
      final k = await _hkdf.deriveKey(
        secretKey: master,
        nonce: const <int>[],
        info: utf8.encode('ergos/v1/$info'),
      );
      return Uint8List.fromList(await k.extractBytes());
    }

    return DerivedKeys(await sub('sqlcipher'), await sub('drive-blobs'));
  }

  static String hex(List<int> b) =>
      b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  // ---------------------------------------------------------------- blobs

  /// Formato: "ERG1" | nonce(12) | ciphertext | tag(16)
  Future<Uint8List> encryptBytes(Uint8List plain, Uint8List key,
      {List<int> aad = const []}) async {
    final box = await _aes.encrypt(plain, secretKey: SecretKey(key), aad: aad);
    return Uint8List.fromList([..._magicBlob, ...box.concatenation()]);
  }

  Future<Uint8List> decryptBytes(Uint8List data, Uint8List key,
      {List<int> aad = const []}) async {
    if (data.length < 4 + 12 + 16 ||
        !_startsWith(data, _magicBlob)) {
      throw const FormatException('Blob Ergos inválido');
    }
    final box = SecretBox.fromConcatenation(data.sublist(4),
        nonceLength: 12, macLength: 16);
    // Lanza SecretBoxAuthenticationError si la llave es incorrecta o hay manipulación.
    return Uint8List.fromList(
        await _aes.decrypt(box, secretKey: SecretKey(key), aad: aad));
  }

  Future<Uint8List> encryptJson(Map<String, dynamic> json, Uint8List key,
          {List<int> aad = const []}) =>
      encryptBytes(Uint8List.fromList(utf8.encode(jsonEncode(json))), key,
          aad: aad);

  Future<Map<String, dynamic>> decryptJson(Uint8List data, Uint8List key,
      {List<int> aad = const []}) async {
    final plain = await decryptBytes(data, key, aad: aad);
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }

  // ------------------------------------------------------- archivos grandes

  /// Cifra un video por fragmentos de 1 MiB (memoria constante).
  /// Cada fragmento lleva como AAD su índice y si es el último, para impedir
  /// reordenar, duplicar o truncar fragmentos.
  Future<void> encryptFile(File src, File dst, Uint8List key) async {
    final raf = await src.open();
    final out = dst.openWrite();
    try {
      out.add(_magicVideo);
      final len = await raf.length();
      var index = 0;
      var offset = 0;
      do {
        final n = min(chunkSize, len - offset);
        final chunk = await raf.read(n);
        offset += n;
        final last = offset >= len;
        final enc = await _aes.encrypt(chunk,
            secretKey: SecretKey(key), aad: _chunkAad(index, last));
        final bytes = enc.concatenation();
        out.add(_u32(bytes.length));
        out.add(bytes);
        index++;
      } while (offset < len);
    } finally {
      await raf.close();
      await out.flush();
      await out.close();
    }
  }

  /// Descifra a un archivo temporal para reproducirlo (borrar al cerrar el visor).
  Future<void> decryptFile(File src, File dst, Uint8List key) async {
    final raf = await src.open();
    final out = dst.openWrite();
    try {
      final head = await raf.read(4);
      if (!_startsWith(head, _magicVideo)) {
        throw const FormatException('Video Ergos inválido');
      }
      final total = await raf.length();
      var pos = 4;
      var index = 0;
      while (pos < total) {
        final lenBytes = await raf.read(4);
        final n = ByteData.sublistView(Uint8List.fromList(lenBytes))
            .getUint32(0, Endian.big);
        final body = await raf.read(n);
        pos += 4 + n;
        final last = pos >= total;
        final box = SecretBox.fromConcatenation(body,
            nonceLength: 12, macLength: 16);
        out.add(await _aes.decrypt(box,
            secretKey: SecretKey(key), aad: _chunkAad(index, last)));
        index++;
      }
    } finally {
      await raf.close();
      await out.flush();
      await out.close();
    }
  }

  /// Sobrescribe y elimina un archivo en claro (video recién grabado, PDF temporal).
  /// En SSD/flash no garantiza borrado físico; por eso lo ideal es grabar en un
  /// directorio temporal privado de la app y cifrar de inmediato.
  Future<void> shred(File f) async {
    if (!await f.exists()) return;
    try {
      final len = await f.length();
      final raf = await f.open(mode: FileMode.write);
      final zeros = Uint8List(64 * 1024);
      var w = 0;
      while (w < len) {
        final n = min(zeros.length, len - w);
        await raf.writeFrom(zeros, 0, n);
        w += n;
      }
      await raf.flush();
      await raf.close();
    } catch (_) {}
    await f.delete();
  }

  // ---------------------------------------------------------------- helpers
  List<int> _chunkAad(int index, bool last) =>
      [..._u32(index), last ? 1 : 0];

  List<int> _u32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.big);
    return b.buffer.asUint8List();
  }

  bool _startsWith(List<int> d, List<int> p) {
    for (var i = 0; i < p.length; i++) {
      if (d[i] != p[i]) return false;
    }
    return true;
  }
}
