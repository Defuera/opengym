import 'package:flutter/material.dart';

import '../theme.dart';

class OgChip extends StatelessWidget {
  const OgChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? OG.ink : OG.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: OG.ink, width: 2),
        ),
        child: Text(
          label,
          style: OG.body(
            weight: FontWeight.w600,
            color: selected ? OG.white : OG.ink,
          ),
        ),
      ),
    );
  }
}
