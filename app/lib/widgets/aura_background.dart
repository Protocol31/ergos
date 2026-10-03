import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme/ergos_theme.dart';
import 'stained_glass.dart';

/// Fondo de toda la app: aura verde que respira, vitral tenue y luciérnagas
/// (destellos de sanación). Un solo Ticker, sin shaders: barato en móvil.
class AuraBackground extends StatefulWidget {
  const AuraBackground({super.key, required this.child, this.glassOpacity = .22});
  final Widget child;
  final double glassOpacity;
  @override
  State<AuraBackground> createState() => _AuraBackgroundState();
}

class _AuraBackgroundState extends State<AuraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = reduce ? 0.0 : _c.value * 60;
            return CustomPaint(
              painter: _AuraPainter(t, widget.glassOpacity),
            );
          },
        ),
      ),
      widget.child,
    ]);
  }
}

class _AuraPainter extends CustomPainter {
  _AuraPainter(this.t, this.glassOpacity);
  final double t, glassOpacity;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = Ergos.night);
    // aura principal que respira
    final pulse = .5 + .5 * sin(t * .5);
    final c = Offset(s.width * (.62 + .04 * sin(t * .13)), s.height * .22);
    canvas.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = RadialGradient(
          colors: [Ergos.glow.withOpacity(.10 + .05 * pulse), Ergos.eucalyptus.withOpacity(.14), Colors.transparent],
          stops: const [0, .35, 1],
        ).createShader(Rect.fromCircle(center: c, radius: s.longestSide * .75)),
    );
    canvas.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = RadialGradient(
          colors: [Ergos.moss.withOpacity(.45), Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(s.width * .1, s.height * .95), radius: s.longestSide * .6)),
    );
    // vitral muy tenue como textura
    StainedGlassPainter(seed: 11, cells: 70, reveal: 1, time: t, opacity: glassOpacity, lead: 1.2, lightOrigin: Offset(.62, .22))
        .paint(canvas, s);
    // luciérnagas
    final rnd = Random(3);
    for (var i = 0; i < 28; i++) {
      final bx = rnd.nextDouble(), by = rnd.nextDouble(), sp = .01 + rnd.nextDouble() * .02, ph = rnd.nextDouble() * 6.28;
      final x = (bx + .03 * sin(t * .3 + ph)) * s.width;
      final y = ((by - t * sp) % 1.0) * s.height;
      final tw = .35 + .65 * (.5 + .5 * sin(t * 1.4 + ph));
      canvas.drawCircle(Offset(x, y), 7, Paint()..color = Ergos.glow.withOpacity(.07 * tw)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(Offset(x, y), 1.4, Paint()..color = Ergos.lichen.withOpacity(.65 * tw));
    }
  }

  @override
  bool shouldRepaint(_AuraPainter o) => o.t != t;
}
