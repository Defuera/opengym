import 'package:flutter/material.dart';

import '../theme.dart';
import 'body_figure_shapes.dart';
import 'body_legend.dart';

/// How a limit shows on the figure. Cleared limits are not drawn.
enum LimitMark { active, improving }

/// The blocky body, front and back side by side.
///
/// Colour shows load (0..3 per muscle key). A limit shows red (active) or
/// amber (improving). A black outline marks a focus muscle. Every shape is a
/// tap target of at least 32 px; [onTap] gets the part key. A joint reports
/// its side ("left_knee"); the left side of the person is on the viewer's
/// right in the front view and on the viewer's left in the back view.
class BodyFigure extends StatelessWidget {
  const BodyFigure({
    super.key,
    required this.load,
    required this.onTap,
    this.limits = const <String, LimitMark>{},
    this.focus = const <String>{},
    this.selected,
    this.loadOnly = false,
  });

  /// The legend shows only the load colours.
  final bool loadOnly;

  /// Muscle key -> level 0..3. A missing key means 0.
  final Map<String, int> load;

  /// Part key -> mark. `wrists` marks both wrists; `shoulders` both shoulders.
  final Map<String, LimitMark> limits;

  /// Muscle keys the user's goals name.
  final Set<String> focus;

  /// The part key the user tapped last, if any.
  final String? selected;
  final ValueChanged<String> onTap;

  /// Key of one tap target: [view] is `front` or `back`, [side] is the viewer
  /// side (`l`, `r`) or `c` for the centre.
  static Key shapeKey(String view, String partKey, String side) =>
      ValueKey<String>('$view/$partKey/$side');

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _view('front', true)),
            Expanded(child: _view('back', false)),
          ],
        ),
        const SizedBox(height: 12),
        BodyLegend(loadOnly: loadOnly),
      ],
    );
  }

  Widget _view(String name, bool front) {
    return Column(
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: AspectRatio(
              aspectRatio: figureWidth / figureHeight,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) {
                  final double s = c.maxWidth / figureWidth;
                  final List<BodyShape> shapes = bodyShapes(front);
                  return Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _FigurePainter(
                            shapes: shapes,
                            scale: s,
                            load: load,
                            limits: limits,
                            focus: focus,
                            selected: selected,
                          ),
                        ),
                      ),
                      for (final BodyShape sh in shapes) _target(name, sh, s),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name.toUpperCase(),
          style: OG.muted(size: 13, weight: FontWeight.w700).copyWith(letterSpacing: 0.8),
        ),
      ],
    );
  }

  Widget _target(String view, BodyShape sh, double s) {
    final double w = (sh.w * s) < minTargetPx ? minTargetPx : sh.w * s;
    final double h = (sh.h * s) < minTargetPx ? minTargetPx : sh.h * s;
    return Positioned(
      left: (sh.x + sh.w / 2) * s - w / 2,
      top: (sh.y + sh.h / 2) * s - h / 2,
      width: w,
      height: h,
      child: Semantics(
        button: true,
        label: sh.key.replaceAll('_', ' '),
        child: GestureDetector(
          key: shapeKey(view, sh.key, sh.side),
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(sh.key),
        ),
      ),
    );
  }
}

class _FigurePainter extends CustomPainter {
  _FigurePainter({
    required this.shapes,
    required this.scale,
    required this.load,
    required this.limits,
    required this.focus,
    required this.selected,
  });

  final List<BodyShape> shapes;
  final double scale;
  final Map<String, int> load;
  final Map<String, LimitMark> limits;
  final Set<String> focus;
  final String? selected;

  LimitMark? _mark(BodyShape sh) {
    LimitMark? best;
    for (final String k in <String>[
      sh.key,
      if (sh.muscle != null) sh.muscle!,
      if (sh.key.endsWith('_wrist')) 'wrists',
    ]) {
      final LimitMark? m = limits[k];
      if (m == LimitMark.active) {
        return m;
      }
      best ??= m;
    }
    return best;
  }

  bool _isSelected(BodyShape sh) {
    final String? s = selected;
    if (s == null) {
      return false;
    }
    return s == sh.key ||
        (sh.muscle != null && s == sh.muscle) ||
        (s == 'wrists' && sh.key.endsWith('_wrist'));
  }

  RRect _rr(Rect r, double rx) =>
      RRect.fromRectAndRadius(Rect.fromLTWH(r.left * scale, r.top * scale, r.width * scale, r.height * scale),
          Radius.circular(rx * scale));

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..style = PaintingStyle.fill;
    fill.color = OG.soft;
    canvas.drawCircle(Offset(75 * scale, 22 * scale), 16 * scale, fill);
    for (final double x in <double>[25, 125]) {
      canvas.drawCircle(Offset(x * scale, 191 * scale), 9 * scale, fill);
    }
    for (final BodyShape sh in shapes) {
      final LimitMark? mark = _mark(sh);
      final Color markColor = mark == LimitMark.active ? limitRed : limitAmber;
      if (!sh.hidden) {
        final int level = sh.muscle == null ? 0 : (load[sh.muscle] ?? 0).clamp(0, 3);
        fill.color = (mark != null && !sh.dot) ? markColor : loadColors[level];
        canvas.drawRRect(_rr(sh.rect, sh.rx), fill);
      }
      if (sh.muscle != null && focus.contains(sh.muscle)) {
        canvas.drawRRect(
          _rr(sh.rect, sh.rx),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = OG.ink,
        );
      }
      if (mark != null && !sh.dot) {
        canvas.drawRRect(
          _rr(sh.rect.inflate(4), sh.rx + 4),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = markColor.withValues(alpha: 0.45),
        );
      }
      if (mark != null && sh.dot) {
        final Offset c = Offset((sh.x + sh.w / 2) * scale, (sh.y + (sh.hidden ? sh.h / 2 : 4)) * scale);
        canvas.drawCircle(c, 6 * scale, Paint()..color = OG.white);
        canvas.drawCircle(c, 4.5 * scale, Paint()..color = markColor);
      }
      if (_isSelected(sh)) {
        canvas.drawRRect(
          _rr(sh.rect.inflate(3.5), sh.rx + 3.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = OG.ink,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FigurePainter o) =>
      o.scale != scale ||
      o.selected != selected ||
      o.load != load ||
      o.limits != limits ||
      o.focus != focus;
}
