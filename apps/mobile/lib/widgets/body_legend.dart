import 'package:flutter/material.dart';

import '../theme.dart';
import 'body_figure_shapes.dart';

/// The colour key under the figure.
class BodyLegend extends StatelessWidget {
  const BodyLegend({super.key});

  Widget _item(Color c, String label, {bool outline = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(4),
            border: outline ? Border.all(color: OG.ink, width: 2.5) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: OG.muted(size: 12, weight: FontWeight.w600)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 6,
      children: <Widget>[
        _item(OG.accent, 'Trained most'),
        _item(loadColors[1], 'A little'),
        _item(OG.soft, 'Not trained'),
        _item(limitRed, 'Limit'),
        _item(limitAmber, 'Improving'),
        _item(OG.white, 'Focus', outline: true),
      ],
    );
  }
}
