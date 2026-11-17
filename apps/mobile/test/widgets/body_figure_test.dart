import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/theme.dart';
import 'package:opengym/widgets/body_figure.dart';

const Color _red = Color(0xFFE5482D);
const Color _amber = Color(0xFFF2A93B);
const Color _levelThree = OG.accent;

Future<List<String>> _pump(
  WidgetTester tester, {
  Map<String, int> load = const <String, int>{},
  Map<String, LimitMark> limits = const <String, LimitMark>{},
  Set<String> focus = const <String>{},
  String? selected,
}) async {
  final List<String> taps = <String>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: RepaintBoundary(
            key: const ValueKey<String>('rb'),
            child: ColoredBox(
              color: OG.white,
              child: BodyFigure(
                load: load,
                limits: limits,
                focus: focus,
                selected: selected,
                onTap: taps.add,
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  return taps;
}

/// The colour drawn at a point of one view, in figure units (150 x 326).
Future<Color> _colorAt(WidgetTester t, {required bool front, required double x, required double y}) async {
  final Finder cps = find.descendant(of: find.byType(BodyFigure), matching: find.byType(CustomPaint));
  final Finder cp = front ? cps.first : cps.last;
  final double s = t.getSize(cp).width / 150;
  final Offset origin = t.getTopLeft(cp) - t.getTopLeft(find.byKey(const ValueKey<String>('rb')));
  final RenderRepaintBoundary b =
      t.renderObject(find.byKey(const ValueKey<String>('rb'))) as RenderRepaintBoundary;
  final Color? c = await t.runAsync(() async {
    final ui.Image img = await b.toImage();
    final ByteData d = (await img.toByteData())!;
    final int px = (origin.dx + x * s).round();
    final int py = (origin.dy + y * s).round();
    final int o = (py * img.width + px) * 4;
    return Color.fromARGB(255, d.getUint8(o), d.getUint8(o + 1), d.getUint8(o + 2));
  });
  return c!;
}

bool _isDark(Color c) => c.r < 0.3 && c.g < 0.3 && c.b < 0.3;

void main() {
  testWidgets('load colours the muscles; a muscle with no load stays grey', (WidgetTester t) async {
    await _pump(t, load: const <String, int>{'quads': 3, 'chest': 1});
    expect(await _colorAt(t, front: true, x: 60, y: 200), _levelThree);
    expect(await _colorAt(t, front: true, x: 90, y: 200), _levelThree);
    expect(await _colorAt(t, front: true, x: 62, y: 67), const Color(0xFFC9D3FA));
    expect(await _colorAt(t, front: true, x: 30, y: 100), OG.soft);
    // The back view has no quads: its legs are grey.
    expect(await _colorAt(t, front: false, x: 60, y: 200), OG.soft);
  });

  testWidgets("left knee is red on the viewer's right in front, on the left in back", (WidgetTester t) async {
    await _pump(t, limits: const <String, LimitMark>{'left_knee': LimitMark.active});
    expect(await _colorAt(t, front: true, x: 90, y: 244), _red);
    expect(await _colorAt(t, front: true, x: 60, y: 244), OG.soft);
    expect(await _colorAt(t, front: false, x: 60, y: 244), _red);
    expect(await _colorAt(t, front: false, x: 90, y: 244), OG.soft);
  });

  testWidgets('wrists colours both wrists amber when improving', (WidgetTester t) async {
    await _pump(t, limits: const <String, LimitMark>{'wrists': LimitMark.improving});
    for (final bool front in <bool>[true, false]) {
      expect(await _colorAt(t, front: front, x: 25, y: 176.5), _amber);
      expect(await _colorAt(t, front: front, x: 125, y: 176.5), _amber);
    }
  });

  testWidgets('a right wrist limit colours one wrist only', (WidgetTester t) async {
    await _pump(t, limits: const <String, LimitMark>{'right_wrist': LimitMark.active});
    // Front: the person's right is the viewer's left. Back: the viewer's right.
    expect(await _colorAt(t, front: true, x: 25, y: 176.5), _red);
    expect(await _colorAt(t, front: true, x: 125, y: 176.5), OG.soft);
    expect(await _colorAt(t, front: false, x: 125, y: 176.5), _red);
    expect(await _colorAt(t, front: false, x: 25, y: 176.5), OG.soft);
  });

  testWidgets('a shoulder limit shows as a dot and keeps the load colour', (WidgetTester t) async {
    await _pump(t,
        load: const <String, int>{'shoulders': 2}, limits: const <String, LimitMark>{'left_shoulder': LimitMark.active});
    expect(await _colorAt(t, front: true, x: 116, y: 54), _red);
    expect(await _colorAt(t, front: true, x: 116, y: 70), const Color(0xFF8FA3F4));
    expect(await _colorAt(t, front: true, x: 34, y: 54), const Color(0xFF8FA3F4));
  });

  testWidgets('a focus muscle gets a black outline', (WidgetTester t) async {
    await _pump(t);
    expect(_isDark(await _colorAt(t, front: true, x: 50.3, y: 67)), isFalse);
    await _pump(t, focus: const <String>{'chest'});
    expect(_isDark(await _colorAt(t, front: true, x: 50.3, y: 67)), isTrue);
    // No chest on the back: the back view has no outline there.
    expect(_isDark(await _colorAt(t, front: false, x: 50.3, y: 67)), isFalse);
  });

  testWidgets('a tap reports the part key; sides swap between the views', (WidgetTester t) async {
    final List<String> taps = await _pump(t);
    Future<void> tap(String view, String key, String side) async {
      await t.tap(find.byKey(BodyFigure.shapeKey(view, key, side)));
      await t.pump();
    }

    await tap('front', 'left_knee', 'r');
    await tap('back', 'left_knee', 'l');
    await tap('front', 'right_knee', 'l');
    await tap('front', 'quads', 'l');
    await tap('front', 'chest', 'r');
    await tap('back', 'lats', 'c');
    await tap('back', 'lower_back', 'c');
    await tap('front', 'right_wrist', 'l');
    await tap('back', 'left_wrist', 'l');
    await tap('front', 'left_shoulder', 'r');
    await tap('back', 'neck', 'c');
    expect(taps, <String>[
      'left_knee',
      'left_knee',
      'right_knee',
      'quads',
      'chest',
      'lats',
      'lower_back',
      'right_wrist',
      'left_wrist',
      'left_shoulder',
      'neck',
    ]);
  });

  testWidgets('every tap target is at least 32 px', (WidgetTester t) async {
    await _pump(t);
    final List<Finder> small = <Finder>[
      find.byKey(BodyFigure.shapeKey('front', 'right_wrist', 'l')),
      find.byKey(BodyFigure.shapeKey('front', 'left_wrist', 'r')),
      find.byKey(BodyFigure.shapeKey('back', 'left_wrist', 'l')),
      find.byKey(BodyFigure.shapeKey('front', 'left_knee', 'r')),
      find.byKey(BodyFigure.shapeKey('front', 'neck', 'c')),
      find.byKey(BodyFigure.shapeKey('back', 'right_elbow', 'r')),
    ];
    for (final Finder f in small) {
      final Size size = t.getSize(f);
      expect(size.width, greaterThanOrEqualTo(32));
      expect(size.height, greaterThanOrEqualTo(32));
    }
  });

  testWidgets('the legend names the colours', (WidgetTester t) async {
    await _pump(t);
    for (final String w in <String>['Trained most', 'A little', 'Not trained', 'Limit', 'Improving', 'Focus']) {
      expect(find.text(w), findsOneWidget);
    }
    expect(find.text('FRONT'), findsOneWidget);
    expect(find.text('BACK'), findsOneWidget);
  });
}
