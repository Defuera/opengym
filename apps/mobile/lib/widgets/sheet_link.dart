import 'package:flutter/material.dart';

import '../theme.dart';

/// A quiet bold text link with a chevron, e.g. "Import old training data".
class SheetLink extends StatelessWidget {
  const SheetLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('$label ›', style: OG.muted(weight: FontWeight.w700)),
      ),
    );
  }
}
