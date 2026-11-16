import 'package:flutter/material.dart';

import '../theme.dart';

/// Thick bordered bar. [fraction] is 0..1; null draws an empty bar.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.fraction, this.height = 18});

  final double? fraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    final double f = (fraction ?? 0).clamp(0.0, 1.0).toDouble();
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: OG.soft,
        borderRadius: BorderRadius.circular(height),
        border: Border.all(color: OG.ink, width: OG.borderWidth),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: f,
            heightFactor: 1,
            child: const ColoredBox(color: OG.accent),
          ),
        ),
      ),
    );
  }
}
