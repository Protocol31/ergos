import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/ergos_theme.dart';
import 'features/auth/gate_screen.dart';
import 'features/dashboard/shell.dart';
import 'features/intro/intro_screen.dart';
import 'providers.dart';
import 'widgets/aura_background.dart';

/// Flujo: Intro -> Acceso (frase + 2FA) -> Panel.
/// Al bloquear (inactividad o botón) la sesión se destruye y se vuelve al acceso.
class ErgosApp extends ConsumerStatefulWidget {
  const ErgosApp({super.key});
  @override
  ConsumerState<ErgosApp> createState() => _ErgosAppState();
}

class _ErgosAppState extends ConsumerState<ErgosApp> with WidgetsBindingObserver {
  bool _introDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Bloqueo automático al pasar a segundo plano (móvil) o minimizar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      ref.read(sessionProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return MaterialApp(
      title: 'Ergos',
      debugShowCheckedModeBanner: false,
      theme: Ergos.theme(),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 700),
        child: !_introDone
            ? IntroScreen(key: const ValueKey('intro'), onDone: () => setState(() => _introDone = true))
            : session == null
                ? const AuraBackground(key: ValueKey('gate'), child: Scaffold(backgroundColor: Colors.transparent, body: SafeArea(child: GateScreen())))
                : const AuraBackground(key: ValueKey('shell'), child: ErgosShell()),
      ),
    );
  }
}
