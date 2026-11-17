import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A small on/off control with a label, such as "Last rep failed".
/// Taps flip it through [onChanged]. Left-aligned, takes only the width it needs.
class FlagToggle extends StatelessWidget {
  const FlagToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final Color fg = value ? OG.white : OG.ink;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onChanged(!value);
        },
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: value ? OG.ink : OG.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: OG.ink, width: OG.borderWidth),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                value ? Icons.check_box : Icons.check_box_outline_blank,
                size: 22,
                color: fg,
              ),
              const SizedBox(width: 8),
              Text(label, style: OG.body(size: 15, weight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
