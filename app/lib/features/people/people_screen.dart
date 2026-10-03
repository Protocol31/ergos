import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/ergos_theme.dart';
import '../../providers.dart';
import '../../widgets/stained_glass.dart';
import 'person_detail.dart';
import 'person_form.dart';

class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});
  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    ref.watch(dataVersionProvider);
    final repo = ref.watch(sessionProvider)!.repo;
    final people = repo.people(filter: _filter);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Ergos.glow,
        foregroundColor: Ergos.night,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo feligrés'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PersonForm())),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 100), children: [
        Text('Feligreses', style: t.headlineLarge),
        const SizedBox(height: 14),
        TextField(onChanged: (v) => setState(() => _filter = v), decoration: const InputDecoration(hintText: 'Filtrar por nombre, ocupación, tema…', prefixIcon: Icon(Icons.filter_list))),
        const SizedBox(height: 16),
        if (people.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('Sin resultados'))),
        for (final p in people)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonDetail(personId: p.id))),
              child: Row(children: [
                CircleAvatar(backgroundColor: Ergos.moss, child: Text(p.firstName.isEmpty ? '?' : p.firstName[0].toUpperCase(), style: const TextStyle(color: Ergos.glow))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.fullName, style: t.titleMedium),
                  Text([if (p.age != null) '${p.age} años', if (p.occupation?.isNotEmpty == true) p.occupation!].join(' · '), style: t.bodySmall?.copyWith(color: Ergos.sage)),
                ])),
                _ConsentChip(p.consentStatus),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _ConsentChip extends StatelessWidget {
  const _ConsentChip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final ok = status == 'firmado';
    return Chip(
      avatar: Icon(ok ? Icons.verified_outlined : Icons.pending_outlined, size: 16, color: ok ? Ergos.glow : Ergos.danger),
      label: Text(ok ? 'Consentimiento' : status == 'revocado' ? 'Revocado' : 'Pendiente'),
      backgroundColor: Colors.transparent,
      side: BorderSide(color: (ok ? Ergos.glow : Ergos.danger).withOpacity(.5)),
    );
  }
}
