import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/ergos_theme.dart';
import '../../data/sync/drive_auth.dart';
import '../../data/sync/drive_sync_service.dart';
import '../../providers.dart';
import '../../widgets/stained_glass.dart';
import '../consent/consent_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _status = '';
  bool _busy = false;
  final _auth = DriveAuth.forPlatform();

  Future<void> _connect() async {
    setState(() { _busy = true; _status = 'Conectando con Google…'; });
    try {
      final client = await _auth.signIn();
      if (client == null) { setState(() => _status = 'Cancelado'); return; }
      final s = ref.read(sessionProvider)!;
      ref.read(driveProvider.notifier).state = DriveSyncService(
        client: client, repo: s.repo, crypto: ref.read(cryptoProvider), blobKey: s.session.keys.blobKey);
      await _sync();
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    final d = ref.read(driveProvider);
    if (d == null) return;
    setState(() { _busy = true; _status = 'Sincronizando…'; });
    try {
      final s = ref.read(sessionProvider)!;
      final rep = await d.sync(onProgress: (m) => setState(() => _status = m));
      await ConsentService(crypto: ref.read(cryptoProvider), repo: s.repo, blobKey: s.session.keys.blobKey, drive: d).flushOutbox();
      ref.read(dataVersionProvider.notifier).state++;
      setState(() => _status = 'Listo · $rep');
    } catch (e) {
      setState(() => _status = 'Error de sincronización: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final repo = ref.watch(sessionProvider)!.repo;
    final drive = ref.watch(driveProvider);
    final last = repo.kv('last_sync');
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Seguridad y respaldo', style: t.headlineLarge),
      const SizedBox(height: 16),
      GlassCard(glow: drive != null, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.cloud_sync_outlined, color: Ergos.glow), const SizedBox(width: 12), Text('Google Drive', style: t.titleLarge)]),
        const SizedBox(height: 8),
        Text('Solo se suben archivos cifrados con tu frase maestra. Google no puede leerlos.', style: t.bodySmall?.copyWith(color: Ergos.sage)),
        const SizedBox(height: 14),
        Row(children: [
          FilledButton.icon(onPressed: _busy ? null : (drive == null ? _connect : _sync), icon: Icon(drive == null ? Icons.link : Icons.sync), label: Text(drive == null ? 'Conectar Drive' : 'Sincronizar ahora')),
          const SizedBox(width: 12),
          if (drive != null) TextButton(onPressed: () async { await _auth.signOut(); ref.read(driveProvider.notifier).state = null; }, child: const Text('Desconectar')),
        ]),
        if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_status)),
        if (last != null) Text('Última sincronización: ${DateFormat.yMd('es').add_Hm().format(DateTime.fromMillisecondsSinceEpoch(int.parse(last)))}', style: t.bodySmall),
      ])),
      const SizedBox(height: 14),
      GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.fingerprint, color: Ergos.glow), const SizedBox(width: 12), Text('Biometría en este dispositivo', style: t.titleLarge)]),
        const SizedBox(height: 8),
        const Text('Evita escribir la frase maestra. El código de 6 dígitos sigue siendo obligatorio.'),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: () async {
          final auth = ref.read(authProvider);
          if (!await auth.biometricsAvailable) { setState(() => _status = 'Este dispositivo no tiene biometría disponible.'); return; }
          await auth.enableBiometrics(ref.read(sessionProvider)!.session);
          setState(() => _status = 'Biometría activada');
        }, child: const Text('Activar')),
      ])),
      const SizedBox(height: 14),
      GlassCard(child: Row(children: [
        const Icon(Icons.lock_clock_outlined, color: Ergos.glow), const SizedBox(width: 12),
        const Expanded(child: Text('Bloqueo automático a los 5 minutos o al salir de la app.')),
        FilledButton(onPressed: () => ref.read(sessionProvider.notifier).lock(), child: const Text('Bloquear ya')),
      ])),
    ]);
  }
}
