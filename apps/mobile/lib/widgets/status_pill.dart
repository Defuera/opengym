import 'package:flutter/material.dart';

import '../theme.dart';

/// Small rounded status label: Active, Improving, Cleared.
/// [status] is active | improving | cleared.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.status, this.red = false});

  final String label;
  final String status;

  /// Red fill, as on the figure's selection card.
  final bool red;

  @override
  Widget build(BuildContext context) {
    Color bg = OG.ink;
    Color fg = OG.white;
    Color border = OG.ink;
    if (red) {
      bg = const Color(0xFFE5482D);
      border = bg;
    } else if (status == 'improving') {
      bg = OG.accent;
      border = OG.accent;
    } else if (status == 'cleared') {
      bg = Colors.transparent;
      fg = OG.mute;
      border = const Color(0xFFB9B6AD);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 2),
      ),
      child: Text(label, style: OG.body(size: 13, weight: FontWeight.w800, color: fg)),
    );
  }
}
