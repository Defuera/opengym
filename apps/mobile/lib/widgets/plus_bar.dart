import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';

/// Bottom bar with the big accent plus button.
class PlusBar extends StatelessWidget {
  const PlusBar({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
      decoration: const BoxDecoration(
        color: OG.card,
        border: Border(top: BorderSide(color: OG.ink, width: 2)),
      ),
      child: Center(
        child: SizedBox(
          width: 84,
          height: 88,
          child: OgButton(
            variant: OgVariant.accent,
            minHeight: 84,
            radius: 22,
            padding: EdgeInsets.zero,
            onPressed: onPressed,
            child: const Icon(Icons.add, size: 44),
          ),
        ),
      ),
    );
  }
}
