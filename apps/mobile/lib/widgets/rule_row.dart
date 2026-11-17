import 'package:flutter/material.dart';

import '../theme.dart';

/// One rule: a kind tag (AVOID, LIGHT, DO) and its text. [kind] is
/// avoid | light | do. Tap it to edit when [onTap] is set.
class RuleRow extends StatelessWidget {
  const RuleRow({super.key, required this.kind, required this.label, required this.text, this.onTap});

  final String kind;
  final String label;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool avoid = kind == 'avoid';
    final bool light = kind == 'light';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 62,
              padding: const EdgeInsets.symmetric(vertical: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: avoid ? OG.ink : light ? OG.soft : OG.card,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: OG.ink, width: 2),
              ),
              child: Text(
                label.toUpperCase(),
                style: OG.body(size: 11, weight: FontWeight.w800, color: avoid ? OG.white : OG.ink)
                    .copyWith(letterSpacing: 0.5),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: OG.body(size: 15))),
          ],
        ),
      ),
    );
  }
}
