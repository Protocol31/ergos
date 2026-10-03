import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme/ergos_theme.dart';

/// Vitral procedural: celdas tipo Voronoi (polígonos de vidrio) con emplomado
/// oscuro, tonos verdes de las referencias y una luz que se propaga desde
/// [lightOrigin]. Sin símbolos religiosos: solo vidrio, luz y fractales.
class StainedGlassPainter extends CustomPainter {
  StainedGlassPainter({
    this.seed = 7,
    this.cells = 90,
    this.reveal = 1,
    this.time = 0,
    this.lightOrigin = const Offset(.5, .45),
    this.lead = 2.2,
    this.opacity = 1,
  });

  final int seed, cells;
  final double reveal; // 0..1: radio de la luz que "enciende" el vitral
  final double time;
  final Offset lightOrigin; // fracción del lienzo
  final double lead, opacity;

  static final _cache = <String, List<_Cell>>{};

  List<_Cell> _build(Size s) {
    final key = '$seed-$cells-${s.width.round()}x${s.height.round()}';
    return _cache.putIfAbsent(key, () {
      final rnd = Random(seed);
      // rejilla con jitter -> celdas orgánicas de tamaño parejo
      final cols = max(3, sqrt(cells * s.width / s.height).round());
      final rows = max(3, (cells / cols).round());
      final cw = s.width / cols, ch = s.height / rows;
      final pts = <Offset>[];
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < cols; x++) {
          pts.add(Offset((x + .15 + rnd.nextDouble() * .7) * cw, (y + .15 + rnd.nextDouble() * .7) * ch));
        }
      }
      final bounds = [Offset.zero, Offset(s.width, 0), Offset(s.width, s.height), Offset(0, s.height)];
      final out = <_Cell>[];
      for (var i = 0; i < pts.length; i++) {
        var poly = List<Offset>.from(bounds);
        for (var j = 0; j < pts.length && poly.length >= 3; j++) {
          if (i == j) continue;
          if ((pts[i] - pts[j]).distance > max(cw, ch) * 3.2) continue;
          poly = _clip(poly, pts[i], pts[j]);
        }
        if (poly.length >= 3) out.add(_Cell(pts[i], poly, rnd.nextDouble()));
      }
      return out;
    });
  }

  // Sutherland-Hodgman contra el semiplano más cercano a `a` que a `b`.
  List<Offset> _clip(List<Offset> poly, Offset a, Offset b) {
    final mid = (a + b) / 2;
    final n = b - a;
    double side(Offset p) => (p - mid).dx * n.dx + (p - mid).dy * n.dy;
    final res = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final c = poly[i], d = poly[(i + 1) % poly.length];
      final sc = side(c), sd = side(d);
      if (sc <= 0) res.add(c);
      if ((sc < 0 && sd > 0) || (sc > 0 && sd < 0)) {
        final t = sc / (sc - sd);
        res.add(Offset(c.dx + (d.dx - c.dx) * t, c.dy + (d.dy - c.dy) * t));
      }
    }
    return res;
  }

  static const _tones = [
    Color(0xFF0B3B2E), Color(0xFF14513D), Color(0xFF1F4D3A), Color(0xFF2A6B50),
    Color(0xFF3A7D63), Color(0xFF4F8F75), Color(0xFF0E4A44), Color(0xFF2F6F5E),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cs = _build(size);
    final origin = Offset(size.width * lightOrigin.dx, size.height * lightOrigin.dy);
    final maxR = size.longestSide * 1.1;
    final leadPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = lead
      ..color = Ergos.lead.withOpacity(.95 * opacity);

    for (final c in cs) {
      final d = (c.center - origin).distance;
      final lit = (1 - (d / (maxR * reveal.clamp(.001, 1))).clamp(0.0, 1.0));
      final litEase = lit * lit * (3 - 2 * lit);
      final tw = .5 + .5 * sin(time * 1.2 + c.phase * 6.28);
      final base = _tones[(c.phase * _tones.length).floor() % _tones.length];
      // el vidrio cerca de la luz vira a lima-amarillo, como en el vitral de referencia
      final glass = Color.lerp(base, Ergos.glow, (litEase * (.45 + .25 * tw)).clamp(0, .85))!;
      final path = Path()..addPolygon(c.poly, true);
      canvas.drawPath(path, Paint()..color = glass.withOpacity(opacity * (.25 + .75 * reveal.clamp(0, 1) * (.4 + .6 * litEase + .0))));
      // textura de vidrio: gradiente interno sutil
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.radial(c.center, 70, [Colors.white.withOpacity(.07 * opacity), Colors.transparent]),
      );
    }
    // emplomado: se dibuja por oleadas, creciendo desde la luz
    for (final c in cs) {
      final d = (c.center - origin).distance;
      if (d > maxR * reveal) continue;
      canvas.drawPath(Path()..addPolygon(c.poly, true), leadPaint);
    }
  }

  @override
  bool shouldRepaint(StainedGlassPainter o) =>
      o.reveal != reveal || o.time != time || o.opacity != opacity || o.seed != seed;
}

class _Cell {
  _Cell(this.center, this.poly, this.phase);
  final Offset center;
  final List<Offset> poly;
  final double phase;
}

/// Tarjeta "de cristal": panel translúcido con borde de plomo y brillo suave.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.glow = false, this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final bool glow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Ergos.moss.withOpacity(.55), Ergos.deepForest.withOpacity(.55)],
            ),
            border: Border.all(color: (glow ? Ergos.glow : Ergos.sage).withOpacity(glow ? .55 : .22), width: 1.1),
            boxShadow: glow ? [BoxShadow(color: Ergos.glow.withOpacity(.18), blurRadius: 30)] : null,
          ),
          child: child,
        ),
      ),
    );
    return onTap == null ? card : InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: card);
  }
}
