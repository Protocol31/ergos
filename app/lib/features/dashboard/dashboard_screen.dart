import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/ergos_theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../widgets/stained_glass.dart';
import '../memories/memory_editor.dart';
import '../people/person_detail.dart';

/// Inicio: búsqueda global instantánea (FTS5), seguimientos pendientes,
/// memorias recientes y cifras clave. Pensado para responder "¿qué hablamos
/// con X sobre Y?" en menos de un segundo.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key, required this.onOpenPeople});
  final VoidCallback onOpenPeople;
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<SearchHit> _hits = [];
  String _query = '';

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      final repo = ref.read(sessionProvider)!.repo;
      setState(() { _query = v; _hits = repo.search(v); });
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dataVersionProvider);
    final repo = ref.watch(sessionProvider)!.repo;
    final stats = repo.stats();
    final follow = repo.followUps();
    final recent = repo.recentMemories();
    final t = Theme.of(context).textTheme;
    final df = DateFormat.yMMMd('es');

    return ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 40), children: [
      Text('Que la luz sostenga lo que hoy te confían', style: t.headlineLarge).animate().fadeIn(duration: 700.ms),
      const SizedBox(height: 18),
      GlassCard(
        glow: true,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: TextField(
          controller: _q,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Busca por nombre, tema, batalla, oración, acuerdo…  (ej. "ansiedad trabajo")',
            prefixIcon: Icon(Icons.search_rounded, color: Ergos.glow),
            border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false,
          ),
        ),
      ),
      const SizedBox(height: 18),
      if (_query.trim().isNotEmpty) ...[
        Text('${_hits.length} resultado(s)', style: t.labelLarge?.copyWith(color: Ergos.sage)),
        const SizedBox(height: 8),
        if (_hits.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nada coincide todavía.')),
        for (final h in _hits)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonDetail(personId: h.personId))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(h.kind == 'person' ? Icons.person_outline : Icons.menu_book_outlined, color: Ergos.sage),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.kind == 'person' ? h.personName : '${h.title} · ${h.personName}', style: t.titleMedium),
                  if (h.when != null) Text(df.format(DateTime.fromMillisecondsSinceEpoch(h.when!)), style: t.bodySmall?.copyWith(color: Ergos.sage)),
                  const SizedBox(height: 4),
                  _Snippet(h.snippet),
                ])),
              ]),
            ),
          ),
      ] else ...[
        Wrap(spacing: 14, runSpacing: 14, children: [
          _Stat('Feligreses', '${stats.people}', Icons.people_outline),
          _Stat('Memorias', '${stats.memories}', Icons.menu_book_outlined),
          _Stat('Consentimiento pendiente', '${stats.pendingConsent}', Icons.draw_outlined, warn: stats.pendingConsent > 0),
          _Stat('Seguimientos', '${stats.followUps}', Icons.notifications_none, warn: stats.followUps > 0),
        ]),
        const SizedBox(height: 26),
        Text('Seguimientos próximos', style: t.titleLarge),
        const SizedBox(height: 10),
        if (follow.isEmpty) Text('Sin seguimientos en los próximos 14 días.', style: t.bodyMedium?.copyWith(color: Ergos.sage)),
        for (final m in follow) _MemoryTile(m, trailing: df.format(DateTime.fromMillisecondsSinceEpoch(m.followUpAt!))),
        const SizedBox(height: 26),
        Text('Memorias recientes', style: t.titleLarge),
        const SizedBox(height: 10),
        if (recent.isEmpty)
          GlassCard(child: Column(children: [
            const Text('Aún no hay memorias. Empieza registrando a la primera persona.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: widget.onOpenPeople, child: const Text('Ir a feligreses')),
          ])),
        for (final m in recent) _MemoryTile(m, trailing: df.format(DateTime.fromMillisecondsSinceEpoch(m.occurredAt))),
      ],
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon, {this.warn = false});
  final String label, value;
  final IconData icon;
  final bool warn;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 230,
        child: GlassCard(
          glow: warn,
          child: Row(children: [
            Icon(icon, color: warn ? Ergos.glow : Ergos.sage, size: 28),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Ergos.sage)),
            ]),
          ]),
        ),
      );
}

class _MemoryTile extends ConsumerWidget {
  const _MemoryTile(this.m, {required this.trailing});
  final Memory m;
  final String trailing;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.read(sessionProvider)!.repo.person(m.personId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemoryEditor(personId: m.personId, memoryId: m.id))),
        child: Row(children: [
          const Icon(Icons.auto_stories_outlined, color: Ergos.sage),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.title, style: Theme.of(context).textTheme.titleMedium),
            Text('${p?.fullName ?? ''} · ${memoryKinds[m.kind] ?? m.kind}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Ergos.sage)),
          ])),
          Text(trailing, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

/// Muestra el fragmento de FTS5 resaltando lo que va entre « ».
class _Snippet extends StatelessWidget {
  const _Snippet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final re = RegExp('«(.*?)»');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(color: Ergos.glow, fontWeight: FontWeight.w700)));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return RichText(text: TextSpan(style: Theme.of(context).textTheme.bodySmall, children: spans));
  }
}
