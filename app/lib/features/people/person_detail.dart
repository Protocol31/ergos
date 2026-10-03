import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/ergos_theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../widgets/aura_background.dart';
import '../../widgets/stained_glass.dart';
import '../consent/consent_flow.dart';
import '../memories/memory_editor.dart';
import 'person_form.dart';

class PersonDetail extends ConsumerWidget {
  const PersonDetail({super.key, required this.personId});
  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dataVersionProvider);
    final repo = ref.watch(sessionProvider)!.repo;
    final p = repo.person(personId);
    if (p == null) return const Scaffold(body: Center(child: Text('No encontrado')));
    final mems = repo.memoriesOf(personId);
    final t = Theme.of(context).textTheme;
    final df = DateFormat.yMMMMd('es');
    final signed = p.consentStatus == 'firmado';

    Widget info(String label, String? v) => v == null || v.isEmpty
        ? const SizedBox.shrink()
        : Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.labelMedium?.copyWith(color: Ergos.sage)), const SizedBox(height: 2), Text(v)]));

    return AuraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, title: Text(p.fullName), actions: [
          IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonForm(personId: personId)))),
        ]),
        floatingActionButton: signed
            ? FloatingActionButton.extended(
                backgroundColor: Ergos.glow, foregroundColor: Ergos.night,
                icon: const Icon(Icons.add), label: const Text('Nueva memoria'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemoryEditor(personId: personId))))
            : null,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 100), children: [
              GlassCard(
                glow: signed,
                child: Row(children: [
                  Icon(signed ? Icons.verified_outlined : Icons.draw_outlined, color: signed ? Ergos.glow : Ergos.danger),
                  const SizedBox(width: 14),
                  Expanded(child: Text(signed
                      ? 'Consentimiento firmado${p.consentAt != null ? ' el ${df.format(DateTime.fromMillisecondsSinceEpoch(p.consentAt!))}' : ''}.'
                      : p.consentStatus == 'revocado'
                          ? 'Consentimiento revocado: no registres nuevas memorias.'
                          : 'Falta el consentimiento. Obtenlo antes de registrar memorias.')),
                  if (!signed)
                    FilledButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConsentFlow(personId: personId))), child: const Text('Iniciar')),
                  if (signed)
                    TextButton(
                      onPressed: () async {
                        final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                          title: const Text('¿Registrar revocación?'),
                          content: const Text('La persona retira su consentimiento. Deberás atender su solicitud de supresión según el contrato.'),
                          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Registrar'))]));
                        if (ok == true) { repo.setConsent(personId, 'revocado'); ref.read(dataVersionProvider.notifier).state++; }
                      },
                      child: const Text('Revocar')),
                ]),
              ),
              const SizedBox(height: 16),
              GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p.fullName}${p.age != null ? ' · ${p.age} años' : ''}', style: t.titleLarge),
                const SizedBox(height: 14),
                info('Ocupación', p.occupation), info('Estado civil', p.maritalStatus), info('Hogar', p.household),
                info('Relación con Dios', p.godRelation), info('Vida espiritual', p.spiritualState),
                info('Batallas personales', p.personalBattles), info('Entorno', p.environment),
                info('Variables emocionales', p.mentalNotes), info('Fortalezas', p.strengths),
              ])),
              const SizedBox(height: 22),
              Text('Memorias (${mems.length})', style: t.titleLarge),
              const SizedBox(height: 10),
              for (final m in mems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemoryEditor(personId: personId, memoryId: m.id))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.title, style: t.titleMedium),
                      Text('${df.format(DateTime.fromMillisecondsSinceEpoch(m.occurredAt))} · ${memoryKinds[m.kind] ?? m.kind}', style: t.bodySmall?.copyWith(color: Ergos.sage)),
                      if ((m.summary ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(m.summary!, maxLines: 3, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
