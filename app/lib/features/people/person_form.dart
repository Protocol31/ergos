import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../providers.dart';
import '../../widgets/aura_background.dart';
import '../../widgets/form_bits.dart';

/// Ficha del feligrés con todas las variables: identidad, edad, relación con
/// Dios, batallas personales, entorno y variables emocionales.
class PersonForm extends ConsumerStatefulWidget {
  const PersonForm({super.key, this.personId});
  final String? personId;
  @override
  ConsumerState<PersonForm> createState() => _PersonFormState();
}

class _PersonFormState extends ConsumerState<PersonForm> {
  late final Person _p;
  final _c = <String, TextEditingController>{};
  TextEditingController c(String k, [String? v]) => _c.putIfAbsent(k, () => TextEditingController(text: v ?? ''));

  @override
  void initState() {
    super.initState();
    final repo = ref.read(sessionProvider)!.repo;
    _p = (widget.personId == null ? null : repo.person(widget.personId!)) ?? Person(id: repo.newId());
    c('first', _p.firstName); c('last', _p.lastName); c('birth', _p.birthDate);
    c('phone', _p.phone); c('email', _p.email); c('job', _p.occupation);
    c('marital', _p.maritalStatus); c('house', _p.household);
    c('god', _p.godRelation); c('spirit', _p.spiritualState);
    c('battles', _p.personalBattles); c('env', _p.environment);
    c('mental', _p.mentalNotes); c('strengths', _p.strengths);
  }

  String? _n(String k) => c(k).text.trim().isEmpty ? null : c(k).text.trim();

  void _save() {
    if (c('first').text.trim().isEmpty) return;
    _p
      ..firstName = c('first').text.trim()
      ..lastName = c('last').text.trim()
      ..birthDate = _n('birth')
      ..phone = _n('phone')
      ..email = _n('email')
      ..occupation = _n('job')
      ..maritalStatus = _n('marital')
      ..household = _n('house')
      ..godRelation = _n('god')
      ..spiritualState = _n('spirit')
      ..personalBattles = _n('battles')
      ..environment = _n('env')
      ..mentalNotes = _n('mental')
      ..strengths = _n('strengths');
    ref.read(sessionProvider)!.repo.savePerson(_p);
    ref.read(dataVersionProvider.notifier).state++;
    Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(c('birth').text) ?? DateTime(1985),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('es'),
    );
    if (d != null) setState(() => c('birth').text = d.toIso8601String().substring(0, 10));
  }

  @override
  Widget build(BuildContext context) {
    return AuraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, title: Text(widget.personId == null ? 'Nuevo feligrés' : 'Editar ficha'), actions: [
          TextButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('Guardar')),
        ]),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              sectionTitle(context, 'Quién es'),
              Row(children: [Expanded(child: field(c('first'), 'Nombre')), const SizedBox(width: 12), Expanded(child: field(c('last'), 'Apellido'))]),
              Row(children: [
                Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 14), child: TextField(controller: c('birth'), readOnly: true, onTap: _pickDate, decoration: const InputDecoration(labelText: 'Fecha de nacimiento', suffixIcon: Icon(Icons.calendar_today_outlined))))),
                const SizedBox(width: 12),
                Expanded(child: field(c('job'), 'Ocupación')),
              ]),
              Row(children: [Expanded(child: field(c('phone'), 'Teléfono', type: TextInputType.phone)), const SizedBox(width: 12), Expanded(child: field(c('email'), 'Correo', type: TextInputType.emailAddress))]),
              Row(children: [Expanded(child: field(c('marital'), 'Estado civil')), const SizedBox(width: 12), Expanded(child: field(c('house'), 'Hogar / familia'))]),
              sectionTitle(context, 'Su camino interior'),
              field(c('god'), 'Relación actual con Dios', lines: 3),
              field(c('spirit'), 'Vida espiritual (etapa, práctica, comunidad)', lines: 3),
              field(c('battles'), 'Batallas personales', lines: 3),
              field(c('env'), 'Entorno (familia, trabajo, amistades)', lines: 3),
              field(c('mental'), 'Variables emocionales y mentales', lines: 3, hint: 'Ánimo, ansiedad, sueño, duelo, estrés…'),
              field(c('strengths'), 'Fortalezas y recursos', lines: 2),
              const SizedBox(height: 10),
              FilledButton(onPressed: _save, child: const Text('Guardar ficha')),
            ]),
          ),
        ),
      ),
    );
  }
}
