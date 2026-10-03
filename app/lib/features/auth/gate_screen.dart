import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/ergos_theme.dart';
import '../../providers.dart';
import '../../widgets/stained_glass.dart';

/// Pantalla de acceso: primera vez = configurar; después = desbloquear.
class GateScreen extends ConsumerStatefulWidget {
  const GateScreen({super.key});
  @override
  ConsumerState<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends ConsumerState<GateScreen> {
  bool? _configured;
  bool _bio = false, _bioReady = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final a = ref.read(authProvider);
    final c = await a.isConfigured;
    final b = c && await a.biometricsAvailable && await a.biometricsEnabled;
    if (mounted) setState(() { _configured = c; _bioReady = b; });
  }

  @override
  Widget build(BuildContext context) {
    if (_configured == null) return const SizedBox.shrink();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: GlassCard(
            glow: true,
            padding: const EdgeInsets.all(28),
            child: _configured! ? _Unlock(bioReady: _bioReady, useBio: _bio, onToggleBio: () => setState(() => _bio = !_bio)) : _Setup(onDone: _check),
          ).animate().fadeIn(duration: 600.ms).slideY(begin: .04),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- desbloquear
class _Unlock extends ConsumerStatefulWidget {
  const _Unlock({required this.bioReady, required this.useBio, required this.onToggleBio});
  final bool bioReady, useBio;
  final VoidCallback onToggleBio;
  @override
  ConsumerState<_Unlock> createState() => _UnlockState();
}

class _UnlockState extends ConsumerState<_Unlock> {
  final _pass = TextEditingController(), _code = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _go() async {
    setState(() { _busy = true; _error = null; });
    try {
      final auth = ref.read(authProvider);
      final s = widget.useBio
          ? await auth.unlockWithBiometrics(_code.text)
          : await auth.unlockWithPassphrase(_pass.text, _code.text);
      await ref.read(sessionProvider.notifier).open(s);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'No se pudo abrir: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Ergos', textAlign: TextAlign.center, style: t.displayMedium),
      const SizedBox(height: 4),
      Text('Todo lo que se confía aquí está cifrado.', textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: Ergos.sage)),
      const SizedBox(height: 24),
      if (!widget.useBio)
        TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Frase maestra', prefixIcon: Icon(Icons.key_rounded)), onSubmitted: (_) => _go()),
      if (!widget.useBio) const SizedBox(height: 14),
      TextField(
        controller: _code,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        decoration: const InputDecoration(labelText: 'Código de 6 dígitos (autenticador)', prefixIcon: Icon(Icons.shield_moon_outlined)),
        onSubmitted: (_) => _go(),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Ergos.danger))),
      const SizedBox(height: 20),
      FilledButton(onPressed: _busy ? null : _go, child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Entrar')),
      if (widget.bioReady)
        TextButton.icon(onPressed: widget.onToggleBio, icon: Icon(widget.useBio ? Icons.key_rounded : Icons.fingerprint), label: Text(widget.useBio ? 'Usar frase maestra' : 'Usar huella / rostro')),
    ]);
  }
}

// ----------------------------------------------------------------- configurar
class _Setup extends ConsumerStatefulWidget {
  const _Setup({required this.onDone});
  final VoidCallback onDone;
  @override
  ConsumerState<_Setup> createState() => _SetupState();
}

class _SetupState extends ConsumerState<_Setup> {
  final _pass = TextEditingController(), _pass2 = TextEditingController(), _code = TextEditingController();
  late final String _secret = ref.read(authProvider).newTotpSecret();
  int _step = 0;
  bool _saved = false;
  String? _error;

  Future<void> _finish() async {
    try {
      final auth = ref.read(authProvider);
      final s = await auth.setup(passphrase: _pass.text, totpSecret: _secret, totpCode: _code.text);
      await ref.read(sessionProvider.notifier).open(s);
      final sess = ref.read(sessionProvider)!;
      sess.repo.setKv('salt_b64', base64Encode(await auth.salt)); // se publica en Drive/_meta
      widget.onDone();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final auth = ref.read(authProvider);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Bienvenido a Ergos', textAlign: TextAlign.center, style: t.headlineMedium),
      const SizedBox(height: 18),
      if (_step == 0) ...[
        Text('1 · Tu frase maestra', style: t.titleLarge),
        const SizedBox(height: 6),
        Text('Cifra todo. Nadie puede recuperarla, ni Google ni nosotros: si se pierde, los datos no se pueden abrir. Escríbela en papel y guárdala en un lugar seguro.', style: t.bodySmall?.copyWith(color: Ergos.sage)),
        const SizedBox(height: 14),
        TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Frase (mín. 5 palabras)')),
        const SizedBox(height: 12),
        TextField(controller: _pass2, obscureText: true, decoration: const InputDecoration(labelText: 'Repite la frase')),
        CheckboxListTile(contentPadding: EdgeInsets.zero, value: _saved, onChanged: (v) => setState(() => _saved = v ?? false), title: const Text('La guardé en un lugar físico seguro'), controlAffinity: ListTileControlAffinity.leading),
        if (_error != null) Text(_error!, style: const TextStyle(color: Ergos.danger)),
        FilledButton(
          onPressed: _saved && _pass.text == _pass2.text && _pass.text.trim().split(RegExp(r'\s+')).length >= 5 ? () => setState(() { _step = 1; _error = null; }) : null,
          child: const Text('Continuar'),
        ),
      ] else ...[
        Text('2 · Verificación en dos pasos', style: t.titleLarge),
        const SizedBox(height: 6),
        Text('Escanea con Google Authenticator, Authy o Microsoft Authenticator y escribe el código.', style: t.bodySmall?.copyWith(color: Ergos.sage)),
        const SizedBox(height: 14),
        Center(child: Container(color: Colors.white, padding: const EdgeInsets.all(10), child: QrImageView(data: auth.totpUri(_secret), size: 170))),
        const SizedBox(height: 8),
        SelectableText('Clave manual: $_secret', textAlign: TextAlign.center, style: t.bodySmall),
        const SizedBox(height: 12),
        TextField(controller: _code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Código de 6 dígitos')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Ergos.danger))),
        const SizedBox(height: 14),
        FilledButton(onPressed: _finish, child: const Text('Activar y entrar')),
      ],
    ]);
  }
}
