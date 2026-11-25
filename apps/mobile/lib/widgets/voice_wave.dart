import 'package:flutter/material.dart';

import '../theme.dart';

/// A row of thin vertical bars, one for each recent loudness (0..1), newest on
/// the right. Silence is a flat low line; speech makes tall bars. It takes as
/// many of the newest [levels] as fit; the space at the left stays a flat line.
class VoiceWave extends StatelessWidget {
  const VoiceWave({super.key, required this.levels, this.height = 32});

  final List<double> levels;
  final double height;

  static const double barWidth = 3;
  static const double gap = 3;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _WavePainter(List<double>.of(levels)),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.levels);

  final List<double> levels;

  @override
  void paint(Canvas canvas, Size size) {
    const double step = VoiceWave.barWidth + VoiceWave.gap;
    final int fit = (size.width / step).floor();
    final Paint paint = Paint()..color = OG.ink;
    final double mid = size.height / 2;
    for (int i = 0; i < fit; i++) {
      // Bar 0 is the newest, at the right edge.
      final int at = levels.length - 1 - i;
      final double v = at >= 0 ? levels[at].clamp(0.0, 1.0) : 0;
      // A little lift so a quiet voice shows, then the minimum of a flat line.
      final double h = (VoiceWave.barWidth + (size.height - VoiceWave.barWidth) * _lift(v));
      final double x = size.width - VoiceWave.barWidth - i * step;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - h / 2, VoiceWave.barWidth, h),
          const Radius.circular(VoiceWave.barWidth / 2),
        ),
        paint,
      );
    }
  }

  static double _lift(double v) => v <= 0 ? 0 : (v * 1.15).clamp(0.0, 1.0);

  @override
  bool shouldRepaint(_WavePainter old) => !_same(old.levels, levels);

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
