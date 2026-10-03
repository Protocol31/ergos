import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_service.dart';
import 'core/crypto/crypto_service.dart';
import 'data/db/database.dart';
import 'data/repository.dart';
import 'data/sync/drive_sync_service.dart';

final cryptoProvider = Provider((_) => CryptoService());
final authProvider = Provider((ref) => AuthService(crypto: ref.read(cryptoProvider)));

/// Sesión desbloqueada: llaves + base abierta. Existe solo en memoria.
class AppSession {
  AppSession(this.session, this.db) : repo = Repository(db);
  final Session session;
  final ErgosDatabase db;
  final Repository repo;
}

class SessionNotifier extends StateNotifier<AppSession?> {
  SessionNotifier() : super(null);

  Future<void> open(Session s) async {
    final db = await ErgosDatabase.open(s.keys.dbKey);
    state = AppSession(s, db);
  }

  void lock() {
    state?.db.close();
    state = null; // las llaves salen de memoria con el GC; no se guardan en disco
  }
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, AppSession?>((_) => SessionNotifier());

/// Se incrementa tras cada escritura para refrescar listas y búsquedas.
final dataVersionProvider = StateProvider<int>((_) => 0);

Repository requireRepo(WidgetRef ref) => ref.read(sessionProvider)!.repo;

/// Servicio de Drive; null mientras la cuenta de Google no esté conectada.
final driveProvider = StateProvider<DriveSyncService?>((_) => null);
