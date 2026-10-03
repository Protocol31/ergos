import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/ergos_theme.dart';
import '../../providers.dart';
import '../people/people_screen.dart';
import '../settings/settings_screen.dart';
import 'dashboard_screen.dart';

/// Escritorio (>= 900 px): barra lateral. Móvil: barra inferior.
/// Bloqueo automático tras 5 min sin actividad.
class ErgosShell extends ConsumerStatefulWidget {
  const ErgosShell({super.key});
  @override
  ConsumerState<ErgosShell> createState() => _ErgosShellState();
}

class _ErgosShellState extends ConsumerState<ErgosShell> {
  int _i = 0;
  Timer? _idle;
  static const _timeout = Duration(minutes: 5);

  void _touch() {
    _idle?.cancel();
    _idle = Timer(_timeout, () => ref.read(sessionProvider.notifier).lock());
  }

  @override
  void initState() {
    super.initState();
    _touch();
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  static const _dest = [
    (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Inicio'),
    (Icons.people_outline, Icons.people, 'Feligreses'),
    (Icons.lock_outline, Icons.lock, 'Seguridad'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final pages = [
      DashboardScreen(onOpenPeople: () => setState(() => _i = 1)),
      const PeopleScreen(),
      const SettingsScreen(),
    ];
    final body = AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: KeyedSubtree(key: ValueKey(_i), child: pages[_i]));
    return Listener(
      onPointerDown: (_) => _touch(),
      onPointerSignal: (_) => _touch(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _i,
                onDestinationSelected: (v) => setState(() => _i = v),
                destinations: [for (final d in _dest) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2, color: Ergos.glow), label: d.$3)],
              ),
        body: SafeArea(
          child: Row(children: [
            if (wide)
              NavigationRail(
                selectedIndex: _i,
                onDestinationSelected: (v) => setState(() => _i = v),
                labelType: NavigationRailLabelType.all,
                leading: Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text('ERGOS', style: Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing: 6, color: Ergos.glow))),
                destinations: [for (final d in _dest) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3))],
              ),
            Expanded(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1180), child: body))),
          ]),
        ),
      ),
    );
  }
}
