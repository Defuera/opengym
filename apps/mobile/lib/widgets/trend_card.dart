import 'package:flutter/material.dart';

import '../theme.dart';

/// Simple line chart (no packages). [values] are drawn left to right.
class TrendCard extends StatelessWidget {
  const TrendCard({
    super.key,
    required this.title,
    required this.unit,
    required this.values,
  });

  final String title;
  final String unit;
  final List<double> values;

  static String _fmt(double v) {
    final double r = (v * 10).round() / 10;
    return r == r.truncateToDouble() ? '${r.toInt()}' : '$r';
  }

  @override
  Widget build(BuildContext context) {
    final bool has = values.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ogBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(title, style: OG.body(size: 18, weight: FontWeight.w700)),
              ),
              if (has)
                Text('${_fmt(values.last)} $unit',
                    style: OG.body(weight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            width: double.infinity,
            child: has
                ? CustomPaint(painter: TrendPainter(values))
                : Center(child: Text('Not enough data yet.', style: OG.muted())),
          ),
        ],
      ),
    );
  }
}

class TrendPainter extends CustomPainter {
  TrendPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint base = Paint()
      ..color = OG.soft
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), base);
    if (values.isEmpty) {
      return;
    }
    double lo = values.first;
    double hi = values.first;
    for (final double v in values) {
      if (v < lo) {
        lo = v;
      }
      if (v > hi) {
        hi = v;
      }
    }
    final double span = (hi - lo) == 0 ? 1 : (hi - lo);
    const double pad = 8;
    final double w = size.width - pad * 2;
    final double h = size.height - pad * 2;
    final List<Offset> pts = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final double x = values.length == 1
          ? size.width / 2
          : pad + w * i / (values.length - 1);
      final double y = (hi - lo) == 0
          ? size.height / 2
          : pad + h * (1 - (values[i] - lo) / span);
      pts.add(Offset(x, y));
    }
    final Paint line = Paint()
      ..color = OG.accent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Path path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, line);
    final Paint fill = Paint()..color = OG.ink;
    for (final Offset p in pts) {
      canvas.drawCircle(p, 4, fill);
    }
  }

  @override
  bool shouldRepaint(covariant TrendPainter oldDelegate) =>
      oldDelegate.values != values;
}
