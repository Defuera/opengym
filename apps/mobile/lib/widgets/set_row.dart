import 'package:flutter/material.dart';

import '../theme.dart';
import 'set_check.dart';

/// Round badge used by set rows: the set number, or a plus. A done set keeps
/// its number (dimmed); the check control at the right shows the state.
class SetBadge extends StatelessWidget {
  const SetBadge({
    super.key,
    this.number,
    this.done = false,
    this.accent = false,
    this.dashed = false,
  });

  final int? number;
  final bool done;
  final bool accent;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final bool dim = dashed || (done && !accent);
    final Color fill = accent ? OG.accent : Colors.transparent;
    final Color edge = accent ? OG.accent : (dim ? OG.mute : OG.ink);
    final Color fg = accent ? OG.white : (dim ? OG.mute : OG.ink);
    final Widget inner = dashed
        ? Icon(Icons.add, size: 16, color: fg)
        : Text('${number ?? ''}', style: OG.body(size: 13, weight: FontWeight.w800, color: fg));
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: dashed ? null : Border.all(color: edge, width: 2),
      ),
      foregroundDecoration: dashed ? _DashedCircle(edge) : null,
      child: inner,
    );
  }
}

class _DashedCircle extends Decoration {
  const _DashedCircle(this.color);

  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _DashedCirclePainter(color);
}

class _DashedCirclePainter extends BoxPainter {
  _DashedCirclePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final Size s = cfg.size ?? Size.zero;
    final Paint p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final Rect r = (offset & s).deflate(1);
    const int dashes = 12;
    for (int i = 0; i < dashes; i++) {
      final double a = i * 2 * 3.141592653589793 / dashes;
      canvas.drawArc(r, a, 2 * 3.141592653589793 / dashes * 0.55, false, p);
    }
  }
}

/// One compact set: badge, then "6 × 60 kg". Not the current set, so no steppers.
class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.number,
    required this.reps,
    required this.kg,
    this.done = false,
    this.failed = false,
    this.isMax = false,
    this.onTap,
    this.onCheck,
    this.checkKey,
  });

  final int number;
  final int reps;
  final String kg;
  final bool done;
  final bool failed;
  final bool isMax;
  final VoidCallback? onTap;

  /// Tap on the check control; null hides the control.
  final VoidCallback? onCheck;
  final Key? checkKey;

  /// "6 × 60 kg", or "6½ × 70 kg" when the last rep failed.
  String get label => '$reps${failed ? '½' : ''} × $kg kg';

  @override
  Widget build(BuildContext context) {
    final Color fg = done ? OG.mute : OG.ink;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: const BoxDecoration(
          color: OG.card,
          border: Border(bottom: BorderSide(color: OG.soft, width: 1.5)),
        ),
        child: Row(
          children: <Widget>[
            SetBadge(number: number, done: done),
            const SizedBox(width: 14),
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: '$reps${failed ? '½' : ''}',
                    style: OG.display(20, color: fg),
                  ),
                  TextSpan(
                    text: ' × ',
                    style: OG.body(size: 20, weight: FontWeight.w500, color: OG.mute),
                  ),
                  TextSpan(text: kg, style: OG.display(20, color: fg)),
                  TextSpan(
                    text: ' kg',
                    style: OG.body(size: 13, weight: FontWeight.w500, color: OG.mute),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (isMax)
              Text('Max', style: OG.body(size: 13, weight: FontWeight.w500, color: OG.mute)),
            if (onCheck != null) SetCheck(key: checkKey, done: done, onTap: onCheck!),
          ],
        ),
      ),
    );
  }
}

/// Last list item: dashed badge and "Add set".
class AddSetRow extends StatelessWidget {
  const AddSetRow({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 46,
        child: Row(
          children: <Widget>[
            const SetBadge(dashed: true),
            const SizedBox(width: 14),
            Text('Add set', style: OG.body(size: 15, weight: FontWeight.w700, color: OG.mute)),
          ],
        ),
      ),
    );
  }
}
