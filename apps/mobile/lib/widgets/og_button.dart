import 'package:flutter/material.dart';

import '../theme.dart';
import 'dashed_box.dart';

enum OgVariant { plain, accent, ink, dashed }

/// Bordered hard-shadow button. Min height 56 for big touch targets.
class OgButton extends StatefulWidget {
  const OgButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = OgVariant.plain,
    this.minHeight = 56,
    this.radius = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
    this.alignment = Alignment.center,
    this.shadow = true,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final OgVariant variant;
  final double minHeight;
  final double radius;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;
  final bool shadow;

  @override
  State<OgButton> createState() => _OgButtonState();
}

class _OgButtonState extends State<OgButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) {
      setState(() => _down = v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final OgVariant v = widget.variant;
    final bool dark = v == OgVariant.accent || v == OgVariant.ink;
    final Color bg = v == OgVariant.accent
        ? OG.accent
        : v == OgVariant.ink
            ? OG.ink
            : v == OgVariant.dashed
                ? OG.soft
                : OG.card;
    final Color fg = dark ? OG.white : OG.ink;
    final bool enabled = widget.onPressed != null;
    final bool hasShadow = widget.shadow && v != OgVariant.dashed;

    final Widget content = Container(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      padding: widget.padding,
      alignment: widget.alignment,
      child: DefaultTextStyle(
        style: OG.body(weight: FontWeight.w700, color: fg),
        child: IconTheme(
          data: IconThemeData(color: fg),
          child: widget.child,
        ),
      ),
    );

    final Widget box = v == OgVariant.dashed
        ? DashedBox(radius: widget.radius, child: content)
        : DecoratedBox(
            decoration: ogBox(
              color: bg,
              radius: widget.radius,
              shadow: hasShadow,
              offset: _down ? 1 : 4,
            ),
            child: content,
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPressed,
      onTapDown: enabled ? (TapDownDetails d) => _set(true) : null,
      onTapUp: enabled ? (TapUpDetails d) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Padding(
          padding: EdgeInsets.only(bottom: hasShadow ? 4 : 0),
          child: Transform.translate(
            offset: Offset(0, (_down && hasShadow) ? 3 : 0),
            child: box,
          ),
        ),
      ),
    );
  }
}
