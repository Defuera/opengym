import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';

/// A square choice with an icon over a short label, e.g. "Camera". Three of
/// them start a note from the Log sheet. The first is [primary] (blue).
class NoteTile extends StatelessWidget {
  const NoteTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = primary ? OG.white : OG.ink;
    return OgButton(
      variant: primary ? OgVariant.accent : OgVariant.plain,
      minHeight: 84,
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 30, color: fg),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OG.body(size: 16, weight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}
