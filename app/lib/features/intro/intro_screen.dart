import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/ergos_theme.dart';
import '../../widgets/stained_glass.dart';

/// Animación de apertura (~7 s, se puede saltar con un toque).
///
/// Línea de tiempo (una sola AnimationController, todo GPU):
///   0.0–1.4 s  Polvo cósmico y destellos aparecen en la oscuridad.
///   1.2–3.4 s  La figura emerge de la niebla (asset opcional) y la luz se
///              enciende en su mano: shader GLSL (núcleo + plasma + rayos).
///   3.2–5.4 s  La luz se expande y "enciende" el vitral: el emplomado se
///              dibuja en ondas desde la mano. Pulso háptico en la ignición.
///   5.2–7.0 s  Aparece ERGOS con tracking amplio y la frase. Fundido a la app.
///
/// Para la figura, coloca tu arte (PNG con fondo transparente, ~1600 px de alto)
/// en assets/intro/figura.png. Si no existe, la animación funciona igual con la
/// luz y el vitral (la mano queda implícita en el punto de luz).
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 7000);
  late final AnimationController _c =
      AnimationController(vsync: this, duration: _total)..addStatusListener((s) {
        if (s == AnimationStatus.completed) _finish();
      });
  ui.FragmentShader? _shader;
  bool _haptic = false, _done = false;
  late final List<_Mote> _motes = List.generate(140, (i) => _Mote(Random(i)));

  // Punto de la luz (mano) como fracción del lienzo.
  static const _hand = Offset(.5, .56);

  @override
  void initState() {
    super.initState();
    _load();
    _c.addListener(() {
      if (!_haptic && _c.value > .22) {
        _haptic = true;
        HapticFeedback.mediumImpact();
      }
    });
    _c.forward();
  }

  Future<void> _load() async {
    try {
      final p = await ui.FragmentProgram.fromAsset('shaders/ergos_light.frag');
      if (mounted) setState(() => _shader = p.fragmentShader());
    } catch (_) {
      // Sin shader (p. ej. backend sin soporte): se usa el degradado de respaldo.
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    _shader?.dispose();
    super.dispose();
  }

  double _seg(double a, double b, [Curve curve = Curves.easeInOut]) {
    final t = ((_c.value * 7.0 - a) / (b - a)).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: Scaffold(
        backgroundColor: Ergos.night,
        body: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final dust = _seg(0, 1.4);
            final figure = _seg(1.2, 3.4, Curves.easeOutCubic);
            final ignite = _seg(1.6, 3.6, Curves.easeInOutCubic);
            final spread = _seg(3.2, 5.4, Curves.easeOutCubic);
            final title = _seg(5.2, 6.4, Curves.easeOutCubic);
            final out = _seg(6.4, 7.0);
            final t = _c.value * 7.0;

            return Opacity(
              opacity: 1 - out,
              child: Stack(fit: StackFit.expand, children: [
                // 1) Cielo de bosque nocturno
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, .1),
                      radius: 1.2,
                      colors: [Ergos.deepForest, Ergos.night],
                    ),
                  ),
                ),
                // 2) Vitral que se enciende desde la mano
                CustomPaint(
                  painter: StainedGlassPainter(
                    seed: 21,
                    cells: 110,
                    reveal: spread,
                    time: t,
                    lightOrigin: _hand,
                    lead: 2.4,
                    opacity: .85 * spread,
                  ),
                ),
                // 3) Polvo cósmico y destellos
                CustomPaint(painter: _MotePainter(_motes, t, dust, ignite)),
                // 4) Figura (opcional) emergiendo de la niebla
                Opacity(
                  opacity: figure,
                  child: Transform.scale(
                    scale: .96 + .04 * figure,
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (r) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black, Colors.black, Colors.transparent],
                        stops: [0, .72, 1],
                      ).createShader(r),
                      child: Image.asset(
                        'assets/intro/figura.png',
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                // 5) LA LUZ: shader GPU (o degradado de respaldo)
                _LightLayer(shader: _shader, progress: ignite, time: t, center: _hand),
                // 6) Marca
                Align(
                  alignment: const Alignment(0, .78),
                  child: Opacity(
                    opacity: title,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        'ERGOS',
                        style: GoogleFonts.cormorantGaramond(
                          fontSize: 56,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 26 - 14 * title, // el tracking se cierra al aparecer
                          color: Ergos.lichen,
                          shadows: [Shadow(color: Ergos.glow.withOpacity(.7), blurRadius: 28)],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'memorias vivas',
                        style: GoogleFonts.inter(fontSize: 13, letterSpacing: 5, color: Ergos.sage),
                      ),
                    ]),
                  ),
                ),
                Positioned(
                  right: 16,
                  top: 16,
                  child: SafeArea(
                    child: Opacity(
                      opacity: .5,
                      child: TextButton(onPressed: _finish, child: const Text('Omitir')),
                    ),
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class _LightLayer extends StatelessWidget {
  const _LightLayer({required this.shader, required this.progress, required this.time, required this.center});
  final ui.FragmentShader? shader;
  final double progress, time;
  final Offset center;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _LightPainter(shader, progress, time, center));
}

class _LightPainter extends CustomPainter {
  _LightPainter(this.shader, this.progress, this.time, this.center);
  final ui.FragmentShader? shader;
  final double progress, time;
  final Offset center;

  @override
  void paint(Canvas canvas, Size s) {
    if (progress <= 0) return;
    final sh = shader;
    if (sh != null) {
      sh
        ..setFloat(0, s.width)
        ..setFloat(1, s.height)
        ..setFloat(2, time)
        ..setFloat(3, progress)
        ..setFloat(4, center.dx)
        ..setFloat(5, center.dy);
      canvas.drawRect(Offset.zero & s, Paint()..shader = sh..blendMode = BlendMode.plus);
    } else {
      final c = Offset(s.width * center.dx, s.height * center.dy);
      final r = s.shortestSide * (.05 + .35 * progress);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(colors: [
            Ergos.glow.withOpacity(.95 * progress),
            Ergos.eucalyptus.withOpacity(.35 * progress),
            Colors.transparent,
          ], stops: const [0, .25, 1]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_LightPainter o) => true; // el tiempo cambia en cada frame
}

class _Mote {
  _Mote(Random r)
      : x = r.nextDouble(),
        y = r.nextDouble(),
        z = .3 + r.nextDouble() * .7,
        ph = r.nextDouble() * 6.28,
        gold = r.nextDouble() > .7;
  final double x, y, z, ph;
  final bool gold;
}

/// Destellos cósmicos: parallax lento + titileo; al encender la luz son
/// atraídos suavemente hacia la mano, como esquirlas de energía.
class _MotePainter extends CustomPainter {
  _MotePainter(this.motes, this.t, this.appear, this.pull);
  final List<_Mote> motes;
  final double t, appear, pull;

  @override
  void paint(Canvas canvas, Size s) {
    final hand = Offset(s.width * .5, s.height * .56);
    for (final m in motes) {
      var p = Offset(
        (m.x + .02 * sin(t * .4 * m.z + m.ph)) * s.width,
        ((m.y - t * .012 * m.z) % 1.0) * s.height,
      );
      p = Offset.lerp(p, hand, .22 * pull * m.z)!;
      final tw = .3 + .7 * (.5 + .5 * sin(t * 2.2 * m.z + m.ph));
      final a = appear * tw * m.z;
      final col = m.gold ? Ergos.glow : Ergos.sage;
      canvas.drawCircle(p, 6 * m.z, Paint()..color = col.withOpacity(.10 * a)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawCircle(p, 1.3 * m.z + .4, Paint()..color = Ergos.lichen.withOpacity(.9 * a));
      if (m.z > .85 && tw > .85) {
        // destello en cruz (lens flare mínimo)
        final l = 9 * m.z;
        final ln = Paint()..color = col.withOpacity(.5 * a)..strokeWidth = .8;
        canvas.drawLine(p - Offset(l, 0), p + Offset(l, 0), ln);
        canvas.drawLine(p - Offset(0, l), p + Offset(0, l), ln);
      }
    }
  }

  @override
  bool shouldRepaint(_MotePainter o) => true;
}
