import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';

/// Full-width thumb action with an icon, e.g. "Complete set".
class CtaButton extends StatelessWidget {
  const CtaButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.variant = OgVariant.ink,
    this.iconAfter = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final OgVariant variant;
  final bool iconAfter;

  @override
  Widget build(BuildContext context) {
    final Widget text = Text(label, style: OG.display(24, color: OG.white));
    final Widget ic = Icon(icon, size: 30);
    return SizedBox(
      width: double.infinity,
      child: OgButton(
        variant: variant,
        minHeight: 76,
        radius: 20,
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: iconAfter
              ? <Widget>[text, const SizedBox(width: 8), ic]
              : <Widget>[ic, const SizedBox(width: 8), text],
        ),
      ),
    );
  }
}
