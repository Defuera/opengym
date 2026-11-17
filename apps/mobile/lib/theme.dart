import 'package:flutter/material.dart';

/// Design tokens from the web prototype, plus the shared bordered hard-shadow look.
class OG {
  OG._();

  static const Color ground = Color(0xFFF2F1EC);
  static const Color ink = Color(0xFF121212);
  static const Color card = Color(0xFFFFFFFF);
  static const Color mute = Color(0xFF5C5A55);
  static const Color soft = Color(0xFFE4E2DA);
  static const Color accent = Color(0xFF2448E8);
  static const Color done = Color(0xFFDCE3FF);
  static const Color white = Color(0xFFFFFFFF);

  static const double radius = 16;
  static const double borderWidth = 2;

  /// Display text: system font, heavy weight.
  static TextStyle display(double size, {Color color = ink}) {
    return TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 1.05,
      letterSpacing: -0.5,
      color: color,
    );
  }

  static TextStyle body({
    double size = 17,
    FontWeight weight = FontWeight.w400,
    Color color = ink,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: 1.3,
      color: color,
    );
  }

  static TextStyle muted({double size = 17, FontWeight weight = FontWeight.w400}) {
    return body(size: size, weight: weight, color: mute);
  }
}

/// 2px ink border, rounded corners, hard offset shadow (no blur).
BoxDecoration ogBox({
  Color color = OG.card,
  double radius = OG.radius,
  bool shadow = true,
  double offset = 4,
  Color shadowColor = OG.ink,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: OG.ink, width: OG.borderWidth),
    boxShadow: shadow
        ? <BoxShadow>[
            BoxShadow(
              color: shadowColor,
              offset: Offset(0, offset),
              blurRadius: 0,
            ),
          ]
        : <BoxShadow>[],
  );
}
