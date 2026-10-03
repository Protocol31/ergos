import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Alcance mínimo: `drive.file` = la app solo ve los archivos que ella misma
/// creó. No puede leer el resto del Drive de la cuenta.
const driveScopes = [drive.DriveApi.driveFileScope];

/// Credenciales OAuth creadas en Google Cloud Console (tipo "Desktop" para Windows,
/// "Android"/"iOS" para móvil). Ver docs/ARQUITECTURA.md §5.
class DriveOAuthConfig {
  static const desktopClientId = String.fromEnvironment('ERGOS_DESKTOP_CLIENT_ID');
  static const desktopClientSecret = String.fromEnvironment('ERGOS_DESKTOP_CLIENT_SECRET');
}

abstract class DriveAuth {
  /// Devuelve un cliente HTTP autenticado o null si el usuario cancela.
  Future<http.Client?> signIn();
  Future<void> signOut();

  factory DriveAuth.forPlatform() =>
      (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
          ? _DesktopDriveAuth()
          : _MobileDriveAuth();
}

class _MobileDriveAuth implements DriveAuth {
  final _gsi = GoogleSignIn(scopes: driveScopes);

  @override
  Future<http.Client?> signIn() async {
    final acct = await _gsi.signInSilently() ?? await _gsi.signIn();
    if (acct == null) return null;
    return _gsi.authenticatedClient();
  }

  @override
  Future<void> signOut() => _gsi.signOut();
}

/// Windows: flujo OAuth "loopback" (navegador del sistema + servidor local),
/// con el refresh token guardado en DPAPI vía flutter_secure_storage.
class _DesktopDriveAuth implements DriveAuth {
  static const _k = 'ergos.drive_refresh';
  final _storage = const FlutterSecureStorage();
  gauth.AutoRefreshingAuthClient? _client;

  @override
  Future<http.Client?> signIn() async {
    final id = gauth.ClientId(DriveOAuthConfig.desktopClientId, DriveOAuthConfig.desktopClientSecret);
    final saved = await _storage.read(key: _k);
    if (saved != null) {
      final creds = gauth.AccessCredentials(
        gauth.AccessToken('Bearer', '', DateTime.now().toUtc().subtract(const Duration(days: 1))),
        saved,
        driveScopes,
      );
      _client = gauth.autoRefreshingClient(id, creds, http.Client());
      return _client;
    }
    _client = await gauth.clientViaUserConsent(id, driveScopes, (url) => launchUrl(Uri.parse(url)));
    final rt = _client!.credentials.refreshToken;
    if (rt != null) await _storage.write(key: _k, value: rt);
    return _client;
  }

  @override
  Future<void> signOut() async {
    _client?.close();
    await _storage.delete(key: _k);
  }
}
