import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterCryptography.enable(); // AES/Argon2 nativos cuando la plataforma los ofrece
  runApp(const ProviderScope(child: ErgosApp()));
}
