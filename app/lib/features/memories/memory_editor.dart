import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../providers.dart';
import '../../widgets/aura_background.dart';
import '../../widgets/form_bits.dart';

/// Registro de una conversación / sesión con todas sus variables.
class MemoryEditor extends ConsumerStatefulWidget {
  const MemoryEditor({super.key, required this.personId, this.memoryId});
  final String personId;
  final String? memoryId;
  @override
  ConsumerState<MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends ConsumerState<MemoryEditor> {
  late Memory _m;
  final _c = <String, TextEditingController>{};
  TextEditingController c(String k, [String? v]) => _c.putIfAbsent(k, () => TextEditingController(text: v ?? ''));

  @override
  void initState() {
    super.initState();
    final repo = ref.read(sessionProvider)!.repo;
    Memory? existing;
    if (widget.memoryId != null) {
      existing = repo.memoriesOf(widget.personId).where((x) => x.id == widget.memoryId).firstOrNull;
    }
    _m = existing ?? Memory(id: repo.newId(), personId: widget.personId);
    c('title', _m.title); c('summary', _m.summary); c('body', _m.body);
    c('god', _m.godRelation); c('emo', _m.emotionalState); c('battles', _m.battles);
    c('env', _m.environment); c('prayer', _m.prayerPoints); c('agree', _m.agreements);
    c('next', _m.nextSteps); c('tags', _m.tags);
  }

  String? _n(String k) => c(k).text.trim().isEmpty ? null : c(k).text.trim();

  void _save() {
    if (c('title').text.trim().isEmpty) return;
    _m
      ..title = c('title').text.trim()
      ..summary = _n('summary')
      ..body = _n('body')
      ..godRelation = _n('god')
      ..emotionalState = _n('emo')
      ..battles = _n('battles')
      ..environment = _n('env')
      ..prayerPoints = _n('prayer')
      ..agreements = _n('agree')
      ..nextSteps = _n('next')
      ..tags = _n('tags');
    ref.read(sessionProvider)!.repo.saveMemory(_m);
    ref.read(dataVersionProvider.notifier).state++;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMMd('es');
    return AuraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, title: Text(widget.memoryId == null ? 'Nueva memoria' : 'Memoria'), actions: [
          if (widget.memoryId != null)
            IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline), onPressed: () {
              ref.read(sessionProvider)!.repo.deleteMemory(_m.id);
              ref.read(dataVersionProvider.notifier).state++;
              Navigator.pop(context);
            }),
          TextButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('Guardar')),
        ]),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              field(c('title'), 'Título'),
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(
                  value: _m.kind,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  dropdownColor: const Color(0xFF0B3B2E),
                  items: [for (final e in memoryKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _m.kind = v ?? 'sesion'),
                )),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined),
                  label: Text(df.format(DateTime.fromMillisecondsSinceEpoch(_m.occurredAt))),
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: DateTime.fromMillisecondsSinceEpoch(_m.occurredAt), firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 1)), locale: const Locale('es'));
                    if (d != null) setState(() => _m.occurredAt = d.toUtc().millisecondsSinceEpoch);
                  },
                )),
              ]),
              const SizedBox(height: 14),
              field(c('summary'), 'Resumen', lines: 2),
              field(c('body'), 'Lo conversado', lines: 8),
              sectionTitle(context, 'Variables'),
              field(c('god'), 'Relación con Dios en este momento', lines: 2),
              field(c('emo'), 'Estado emocional / mental', lines: 2),
              field(c('battles'), 'Batallas personales', lines: 2),
              field(c('env'), 'Entorno', lines: 2),
              sectionTitle(context, 'Acompañamiento'),
              field(c('prayer'), 'Motivos de oración', lines: 2),
              field(c('agree'), 'Acuerdos', lines: 2),
              field(c('next'), 'Próximos pasos', lines: 2),
              OutlinedButton.icon(
                icon: const Icon(Icons.notifications_none),
                label: Text(_m.followUpAt == null ? 'Programar seguimiento' : 'Seguimiento: ${df.format(DateTime.fromMillisecondsSinceEpoch(_m.followUpAt!))}'),
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)), locale: const Locale('es'));
                  if (d != null) setState(() => _m.followUpAt = d.toUtc().millisecondsSinceEpoch);
                },
              ),
              const SizedBox(height: 14),
              field(c('tags'), 'Etiquetas (separadas por espacio)', hint: 'duelo familia trabajo'),
              FilledButton(onPressed: _save, child: const Text('Guardar memoria')),
            ]),
          ),
        ),
      ),
    );
  }
}
