import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';

import '../../core/theme/ergos_theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../widgets/aura_background.dart';
import '../../widgets/stained_glass.dart';
import 'consent_service.dart';

/// Asistente de consentimiento: 1 leer · 2 autorizaciones · 3 firma · 4 video · 5 sellar.
/// El video, la firma y el PDF se cifran antes de salir del dispositivo.
class ConsentFlow extends ConsumerStatefulWidget {
  const ConsentFlow({super.key, required this.personId});
  final String personId;
  @override
  ConsumerState<ConsentFlow> createState() => _ConsentFlowState();
}

class _ConsentFlowState extends ConsumerState<ConsentFlow> {
  int _step = 0;
  String _text = '';
  bool _readAll = false, _busy = false;
  final _scroll = ScrollController();
  final _guardian = TextEditingController();
  final _sig = SignatureController(penStrokeWidth: 2.4, penColor: Ergos.lichen, exportBackgroundColor: const Color(0xFF01180F));
  final _checks = <String, bool>{
    'Autorizo el tratamiento de mis datos personales y datos sensibles (salud emocional, creencias) para mi acompañamiento pastoral.': false,
    'Entiendo que el acompañamiento pastoral no sustituye la atención médica ni psicológica profesional.': false,
    'Autorizo el almacenamiento cifrado de mis datos y del video de consentimiento en la nube (Google Drive) del pastor.': false,
    'Autorizo la grabación en video de este consentimiento.': false,
    'Conozco mis derechos de acceso, rectificación, supresión y revocación, y cómo ejercerlos.': false,
  };
  CameraController? _cam;
  bool _recording = false;
  XFile? _video;
  late final Person _person;

  @override
  void initState() {
    super.initState();
    _person = ref.read(sessionProvider)!.repo.person(widget.personId)!;
    rootBundle.loadString('assets/legal/consentimiento_es.md').then((s) {
      final date = DateFormat.yMMMMd('es').format(DateTime.now());
      setState(() => _text = s.replaceAll('{{NOMBRE_TITULAR}}', _person.fullName).replaceAll('{{FECHA}}', date));
    });
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24) {
        if (!_readAll) setState(() => _readAll = true);
      }
    });
  }

  @override
  void dispose() {
    _cam?.dispose();
    _sig.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final cams = await availableCameras();
    if (cams.isEmpty) return;
    final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
    _cam = CameraController(front, ResolutionPreset.medium, enableAudio: true);
    await _cam!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _toggleRecord() async {
    final c = _cam;
    if (c == null) return;
    if (_recording) {
      final f = await c.stopVideoRecording();
      setState(() { _recording = false; _video = f; });
    } else {
      await c.prepareForVideoRecording();
      await c.startVideoRecording();
      setState(() { _recording = true; _video = null; });
    }
  }

  bool get _allChecked => _checks.values.every((v) => v);

  Future<void> _seal() async {
    setState(() => _busy = true);
    try {
      final s = ref.read(sessionProvider)!;
      final png = await _sig.toPngBytes();
      final svc = ConsentService(crypto: ref.read(cryptoProvider), repo: s.repo, blobKey: s.session.keys.blobKey, drive: ref.read(driveProvider));
      final pdf = await svc.buildPdf(
        person: _person,
        contractText: _text,
        accepted: _checks,
        signaturePng: Uint8List.fromList(png!),
        hasVideo: _video != null,
        guardianName: _person.isMinor ? _guardian.text.trim() : null,
      );
      await svc.store(personId: widget.personId, pdf: pdf, signaturePng: Uint8List.fromList(png), plainVideo: _video == null ? null : File(_video!.path));
      ref.read(dataVersionProvider.notifier).state++;
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final steps = ['Leer', 'Autorizar', 'Firmar', 'Video', 'Sellar'];
    final minorNeedsGuardian = _person.isMinor && _guardian.text.trim().length < 3;

    Widget body;
    switch (_step) {
      case 0:
        body = Column(children: [
          Expanded(child: GlassCard(padding: EdgeInsets.zero, child: Scrollbar(controller: _scroll, child: SingleChildScrollView(controller: _scroll, padding: const EdgeInsets.all(22), child: SelectableText(_text.replaceAll(RegExp(r'[#*]'), ''), style: t.bodyMedium?.copyWith(height: 1.55)))))),
          const SizedBox(height: 10),
          Text(_readAll ? 'Lectura completa' : 'Desplázate hasta el final para continuar', style: t.bodySmall?.copyWith(color: _readAll ? Ergos.glow : Ergos.sage)),
        ]);
      case 1:
        body = ListView(children: [
          if (_person.isMinor) ...[
            GlassCard(glow: true, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Menor de edad: debe firmar madre, padre o representante legal.'),
              const SizedBox(height: 10),
              TextField(controller: _guardian, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Nombre del representante legal')),
            ])),
            const SizedBox(height: 12),
          ],
          for (final k in _checks.keys.toList())
            CheckboxListTile(value: _checks[k], onChanged: (v) => setState(() => _checks[k] = v ?? false), title: Text(k), controlAffinity: ListTileControlAffinity.leading, activeColor: Ergos.glow, checkColor: Ergos.night),
        ]);
      case 2:
        body = Column(children: [
          Text('Firma con el dedo, lápiz o mouse', style: t.bodyMedium),
          const SizedBox(height: 10),
          Expanded(child: GlassCard(padding: EdgeInsets.zero, glow: true, child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Signature(controller: _sig, backgroundColor: Colors.transparent)))),
          TextButton.icon(onPressed: _sig.clear, icon: const Icon(Icons.refresh), label: const Text('Borrar')),
        ]);
      case 3:
        body = Column(children: [
          GlassCard(child: Text('Di en voz alta: "Yo, ${_person.fullName}, declaro que he leído y entendido el consentimiento, que acepto libremente que el pastor guarde mis memorias para acompañarme, y que puedo retirar este permiso cuando quiera."')),
          const SizedBox(height: 12),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(20), child: _cam?.value.isInitialized == true ? CameraPreview(_cam!) : Center(child: FilledButton.icon(onPressed: _initCamera, icon: const Icon(Icons.videocam_outlined), label: const Text('Activar cámara'))))),
          const SizedBox(height: 10),
          if (_cam?.value.isInitialized == true)
            FilledButton.icon(onPressed: _toggleRecord, icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.fiber_manual_record), label: Text(_recording ? 'Detener' : _video == null ? 'Grabar' : 'Grabar de nuevo')),
          if (_video != null) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Video capturado. Se cifrará al sellar.')),
        ]);
      default:
        body = Center(child: GlassCard(glow: true, child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.verified_outlined, size: 48, color: Ergos.glow),
          const SizedBox(height: 12),
          Text('Todo listo para sellar', style: t.titleLarge),
          const SizedBox(height: 8),
          const Text('Se generará un PDF con la huella digital del texto, la firma y la fecha. PDF, firma y video se cifran y se guardan en la carpeta de esta persona en Drive.', textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : _seal, child: _busy ? const CircularProgressIndicator() : const Text('Sellar consentimiento')),
        ])));
    }

    final canNext = switch (_step) {
      0 => _readAll && _text.isNotEmpty,
      1 => _allChecked && !minorNeedsGuardian,
      2 => _sig.isNotEmpty,
      3 => _video != null,
      _ => false,
    };

    return AuraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, title: Text('Consentimiento · ${_person.fullName}')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Row(children: [for (var i = 0; i < steps.length; i++) Expanded(child: Column(children: [
                  Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 3), color: i <= _step ? Ergos.glow : Ergos.sage.withOpacity(.2)),
                  const SizedBox(height: 4),
                  Text(steps[i], style: t.labelSmall?.copyWith(color: i <= _step ? Ergos.glow : Ergos.sage)),
                ]))]),
                const SizedBox(height: 16),
                Expanded(child: body),
                const SizedBox(height: 12),
                if (_step < 4)
                  Row(children: [
                    if (_step > 0) OutlinedButton(onPressed: () => setState(() => _step--), child: const Text('Atrás')),
                    const Spacer(),
                    FilledButton(onPressed: canNext ? () => setState(() => _step++) : null, child: const Text('Siguiente')),
                  ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
