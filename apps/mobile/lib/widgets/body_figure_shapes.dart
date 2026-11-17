import 'package:flutter/material.dart';

import '../theme.dart';

const Color limitRed = Color(0xFFE5482D);
const Color limitAmber = Color(0xFFF2A93B);
const List<Color> loadColors = <Color>[
  OG.soft,
  Color(0xFFC9D3FA),
  Color(0xFF8FA3F4),
  OG.accent,
];

/// One tappable drawn shape, in figure units (the figure is 150 x 326).
class BodyShape {
  const BodyShape(
    this.key,
    this.side,
    this.x,
    this.y,
    this.w,
    this.h,
    this.rx, {
    this.muscle,
    this.dot = false,
    this.hidden = false,
  });

  /// The part key a tap reports.
  final String key;

  /// Viewer side: l, r or c (centre).
  final String side;
  final double x, y, w, h, rx;

  /// The muscle key whose load colours this shape.
  final String? muscle;

  /// A limit shows as a dot on the shape instead of a fill (shoulders, elbows).
  final bool dot;

  /// Drawn only when a limit marks it (elbows).
  final bool hidden;

  Rect get rect => Rect.fromLTWH(x, y, w, h);
}

const double figureWidth = 150;
const double figureHeight = 326;
const double minTargetPx = 32;

// The person's sides: in the front view the viewer's left is the person's
// right; in the back view the viewer's left is the person's left.
List<BodyShape> bodyShapes(bool front) {
  final String vl = front ? 'right' : 'left'; // viewer-left side name
  final String vr = front ? 'left' : 'right';
  return <BodyShape>[
    const BodyShape('neck', 'c', 68, 37, 14, 12, 4),
    BodyShape('${vl}_shoulder', 'l', 20, 50, 28, 26, 12, muscle: 'shoulders', dot: true),
    BodyShape('${vr}_shoulder', 'r', 102, 50, 28, 26, 12, muscle: 'shoulders', dot: true),
    if (front) ...const <BodyShape>[
      BodyShape('chest', 'l', 50, 52, 24, 30, 8, muscle: 'chest'),
      BodyShape('chest', 'r', 76, 52, 24, 30, 8, muscle: 'chest'),
      BodyShape('abs', 'c', 54, 86, 42, 46, 10, muscle: 'abs'),
      BodyShape('hips', 'c', 50, 136, 50, 30, 10, muscle: 'hips'),
      BodyShape('biceps', 'l', 19, 80, 22, 44, 10, muscle: 'biceps'),
      BodyShape('biceps', 'r', 109, 80, 22, 44, 10, muscle: 'biceps'),
      BodyShape('quads', 'l', 47, 170, 26, 62, 11, muscle: 'quads'),
      BodyShape('quads', 'r', 77, 170, 26, 62, 11, muscle: 'quads'),
    ] else ...const <BodyShape>[
      BodyShape('upper_back', 'c', 50, 52, 50, 32, 9, muscle: 'upper_back'),
      BodyShape('lats', 'c', 50, 88, 50, 26, 9, muscle: 'lats'),
      BodyShape('lower_back', 'c', 56, 118, 38, 16, 7, muscle: 'lower_back'),
      BodyShape('triceps', 'l', 19, 80, 22, 44, 10, muscle: 'triceps'),
      BodyShape('triceps', 'r', 109, 80, 22, 44, 10, muscle: 'triceps'),
      BodyShape('glutes', 'c', 50, 138, 50, 30, 11, muscle: 'glutes'),
      BodyShape('hamstrings', 'l', 47, 172, 26, 60, 11, muscle: 'hamstrings'),
      BodyShape('hamstrings', 'r', 77, 172, 26, 60, 11, muscle: 'hamstrings'),
    ],
    const BodyShape('forearms', 'l', 15, 128, 20, 42, 9, muscle: 'forearms'),
    const BodyShape('forearms', 'r', 115, 128, 20, 42, 9, muscle: 'forearms'),
    const BodyShape('calves', 'l', 49, 256, 22, 52, 9, muscle: 'calves'),
    const BodyShape('calves', 'r', 79, 256, 22, 52, 9, muscle: 'calves'),
    // Joints last, so they win where hit areas overlap.
    BodyShape('${vl}_elbow', 'l', 19, 118, 22, 16, 6, dot: true, hidden: true),
    BodyShape('${vr}_elbow', 'r', 109, 118, 22, 16, 6, dot: true, hidden: true),
    BodyShape('${vl}_wrist', 'l', 15, 172, 20, 9, 4),
    BodyShape('${vr}_wrist', 'r', 115, 172, 20, 9, 4),
    BodyShape('${vl}_knee', 'l', 50, 236, 20, 16, 8),
    BodyShape('${vr}_knee', 'r', 80, 236, 20, 16, 8),
    BodyShape('${vl}_ankle', 'l', 45, 312, 28, 10, 5),
    BodyShape('${vr}_ankle', 'r', 77, 312, 28, 10, 5),
  ];
}

