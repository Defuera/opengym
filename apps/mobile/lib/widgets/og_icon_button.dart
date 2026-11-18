import 'package:flutter/material.dart';

import 'og_button.dart';

/// Square icon button (close, back). 52 px by default; [size] makes it smaller.
class OgIconButton extends StatelessWidget {
  const OgIconButton({super.key, required this.icon, required this.onPressed, this.size = 52});

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: OgButton(
        minHeight: size,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Icon(icon, size: size < 52 ? 22 : 26),
      ),
    );
  }
}
