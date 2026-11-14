import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A soft-filled box with a dashed 2px ink outline and no shadow.
class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.child,
    this.color = OG.soft,
    this.radius = OG.radius,
  });

  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: CustomPaint(
        foregroundPainter: _DashedPainter(radius: radius),
        child: child,
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  const _DashedPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = OG.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      Radius.circular(radius),
    );
    final Path path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        final double end = math.min(d + 6, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter oldDelegate) {
    return oldDelegate.radius != radius;
  }
}
