import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:otp/otp.dart';

import '../crypto/crypto_service.dart';

/// Resultado de desbloquear: llaves en memoria durante la sesión.
class Session {
  final DerivedKeys keys;
  Session(this.keys);
}

enum UnlockError { wrongPassphrase, wrongCode, locked }

class AuthException implements Exception {
  final UnlockError error;
  final String message;
  AuthException(this.error, this.message);
  @override
  String toString() => message;
}

/// Modelo de seguridad (dos factores reales):
///  1. Algo que sabes: la frase maestra (deriva las llaves de cifrado).
///  2. Algo que tienes: código TOTP del autenticador del pastor.
/// La biometría local (huella / rostro / Windows Hello) sustituye la escritura
/// de la frase maestra en el dispositivo, nunca el TOTP.
///
/// IMPORTANTE: el TOTP protege el acceso a la app; el cifrado de los datos
/// depende de la frase maestra. Si se pierde la frase, los datos no se pueden
/// recuperar (es el precio del cifrado de extremo a extremo): imprimir la
/// "hoja de recuperación" y guardarla en un lugar físico seguro.
class AuthService {
  AuthService({CryptoService? crypto, FlutterSecureStorage? storage})
      : _crypto = crypto ?? CryptoService(),
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  final CryptoService _crypto;
  final FlutterSecureStorage _storage;
  final LocalAuthentication _bio = LocalAuthentication();

  static const _kSalt = 'ergos.salt';
  static const _kCanary = 'ergos.canary';
  static const _kTotp = 'ergos.totp';
  static const _kBioWrap = 'ergos.bio_wrapped';
  static const _kFails = 'ergos.fails';
  static const _kLockUntil = 'ergos.lock_until';
  static const _canaryText = 'ergos-ok';

  Future<bool> get isConfigured async => (await _storage.read(key: _kSalt)) != null;

  // ----------------------------------------------------------- configuración

  /// Genera el secreto TOTP (base32) para mostrarlo como QR.
  String newTotpSecret() => OTP.randomSecret(); // 32 caracteres base32

  String totpUri(String secret, {String account = 'Pastor'}) =>
      'otpauth://totp/Ergos:$account?secret=$secret&issuer=Ergos&algorithm=SHA1&digits=6&period=30';

  bool verifyTotp(String secret, String code) {
    final now = DateTime.now().millisecondsSinceEpoch;
    // tolerancia de +-1 ventana (30 s) por deriva de reloj
    for (final delta in [-30000, 0, 30000]) {
      final expected = OTP.generateTOTPCodeString(
        secret,
        now + delta,
        length: 6,
        interval: 30,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      if (_constEq(expected, code.trim())) return true;
    }
    return false;
  }

  /// Primera ejecución: crea sal, canario de verificación y guarda el TOTP.
  Future<Session> setup({
    required String passphrase,
    required String totpSecret,
    required String totpCode,
  }) async {
    if (passphrase.trim().split(RegExp(r'\s+')).length < 5 || passphrase.length < 20) {
      throw AuthException(UnlockError.wrongPassphrase,
          'Usa una frase de al menos 5 palabras y 20 caracteres.');
    }
    if (!verifyTotp(totpSecret, totpCode)) {
      throw AuthException(UnlockError.wrongCode, 'El código del autenticador no coincide.');
    }
    final salt = _crypto.randomBytes(16);
    final keys = await _crypto.derive(passphrase, salt);
    final canary = await _crypto.encryptBytes(
        Uint8List.fromList(utf8.encode(_canaryText)), keys.blobKey);
    await _storage.write(key: _kSalt, value: base64Encode(salt));
    await _storage.write(key: _kCanary, value: base64Encode(canary));
    await _storage.write(key: _kTotp, value: totpSecret);
    return Session(keys);
  }

  /// La sal es pública (se sube a Drive en _meta/ para poder abrir en otro equipo).
  Future<Uint8List> get salt async =>
      base64Decode((await _storage.read(key: _kSalt))!);

  // -------------------------------------------------------------- desbloqueo

  Future<Session> unlockWithPassphrase(String passphrase, String totpCode) async {
    await _assertNotLocked();
    final totp = await _storage.read(key: _kTotp);
    if (totp == null || !verifyTotp(totp, totpCode)) {
      await _registerFail();
      throw AuthException(UnlockError.wrongCode, 'Código de verificación incorrecto.');
    }
    final keys = await _crypto.derive(passphrase, await salt);
    await _checkCanary(keys);
    await _clearFails();
    return Session(keys);
  }

  /// Biometría + TOTP. Requiere haber activado "enableBiometrics" antes.
  Future<Session> unlockWithBiometrics(String totpCode) async {
    await _assertNotLocked();
    final totp = await _storage.read(key: _kTotp);
    if (totp == null || !verifyTotp(totp, totpCode)) {
      await _registerFail();
      throw AuthException(UnlockError.wrongCode, 'Código de verificación incorrecto.');
    }
    final ok = await _bio.authenticate(
      localizedReason: 'Desbloquear Ergos',
      options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
    );
    if (!ok) throw AuthException(UnlockError.locked, 'Biometría cancelada.');
    final wrapped = await _storage.read(key: _kBioWrap);
    if (wrapped == null) {
      throw AuthException(UnlockError.locked, 'La biometría no está activada.');
    }
    final raw = base64Decode(wrapped);
    final keys = DerivedKeys(
        Uint8List.fromList(raw.sublist(0, 32)), Uint8List.fromList(raw.sublist(32, 64)));
    await _checkCanary(keys);
    await _clearFails();
    return Session(keys);
  }

  Future<bool> get biometricsAvailable async {
    try {
      return await _bio.isDeviceSupported() && (await _bio.canCheckBiometrics);
    } on PlatformException {
      return false;
    }
  }

  Future<bool> get biometricsEnabled async =>
      (await _storage.read(key: _kBioWrap)) != null;

  /// Guarda las llaves en el almacén seguro del sistema (Keystore/Keychain/DPAPI).
  /// Solo se llama con la sesión ya desbloqueada con la frase maestra.
  Future<void> enableBiometrics(Session s) async {
    final ok = await _bio.authenticate(
        localizedReason: 'Activar desbloqueo biométrico en este dispositivo');
    if (!ok) return;
    await _storage.write(
        key: _kBioWrap, value: base64Encode([...s.keys.dbKey, ...s.keys.blobKey]));
  }

  Future<void> disableBiometrics() => _storage.delete(key: _kBioWrap);

  // ------------------------------------------------- anti fuerza bruta local

  Future<void> _assertNotLocked() async {
    final until = int.tryParse(await _storage.read(key: _kLockUntil) ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (until > now) {
      final s = ((until - now) / 1000).ceil();
      throw AuthException(UnlockError.locked, 'Demasiados intentos. Espera $s s.');
    }
  }

  Future<void> _registerFail() async {
    final n = (int.tryParse(await _storage.read(key: _kFails) ?? '') ?? 0) + 1;
    await _storage.write(key: _kFails, value: '$n');
    if (n >= 5) {
      // espera exponencial: 30 s, 60 s, 120 s ... (máx. 1 h)
      final secs = (30 * (1 << (n - 5).clamp(0, 7))).clamp(30, 3600);
      await _storage.write(
          key: _kLockUntil,
          value: '${DateTime.now().millisecondsSinceEpoch + secs * 1000}');
    }
  }

  Future<void> _clearFails() async {
    await _storage.delete(key: _kFails);
    await _storage.delete(key: _kLockUntil);
  }

  Future<void> _checkCanary(DerivedKeys keys) async {
    final c = await _storage.read(key: _kCanary);
    try {
      final plain = await _crypto.decryptBytes(base64Decode(c!), keys.blobKey);
      if (utf8.decode(plain) != _canaryText) throw Exception();
    } catch (_) {
      await _registerFail();
      throw AuthException(UnlockError.wrongPassphrase, 'Frase maestra incorrecta.');
    }
  }

  bool _constEq(String a, String b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return r == 0;
  }
}
