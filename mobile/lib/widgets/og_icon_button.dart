import 'package:flutter/material.dart';

import 'og_button.dart';

/// Square 52px icon button (close, back).
class OgIconButton extends StatelessWidget {
  const OgIconButton({super.key, required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: OgButton(
        minHeight: 52,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Icon(icon, size: 26),
      ),
    );
  }
}
