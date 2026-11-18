// Visual proof of the session screen. Not part of the normal suite (the file
// name has no _test suffix). Run by path:
//   flutter test test/shots/session_ui_shots.dart
// It writes a.png (main), b.png ("Change plan" sheet), c.png ("Why this
// session" sheet with the figure), d.png (rep/kg exercise, set 1 done), e.png
// (time exercise), f.png (all sets done) and g.png (leave sheet) at 390x844
// logical px, pixel ratio 3.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/screens/start_flow.dart';
import 'package:opengym/theme.dart';

import '../support/fake_convex_client.dart';
import '../support/load_fonts.dart';
import '../support/test_deps.dart';

const String _out =
    '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/session-ui';
const String _why =
    'Side delts, shoulder control, shins · Side delts and shins have had little direct work. '
    'Add light shoulder control and shin work, and keep the rest easy so you can recover well before the next hard day.';

Future<void> _save(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final RenderRepaintBoundary b =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image img = await b.toImage(pixelRatio: 3);
    final ByteData? bytes =
        await img.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_out).create(recursive: true);
    await File('$_out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<(AppDeps, GlobalKey)> _open(WidgetTester t, {int sets = 1, FakeConvexClient? client}) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final AppDeps d = await testDeps(client ?? FakeConvexClient());
  d.store.begin(
    activity: 'Home Accessories',
    focus: 'Side delts, shoulder control, shins',
    rationale:
        'Side delts and shins have had little direct work. Add light shoulder control and shin work, '
        'and keep the rest easy so you can recover well before the next hard day.',
    prepared: <Exercise>[
      Exercise(
        id: 'w',
        name: 'Wrist and Hand Warm-Up',
        measure: measureTime,
        fresh: false,
        note:
            'Open and close your hands, circle your wrists, then turn your palms up and down with elbows by your sides.',
        sets: <SetEntry>[SetEntry.time(2)],
      ),
      Exercise(
          id: 'l',
          name: 'Lateral Raise',
          fresh: false,
          sets: <SetEntry>[for (int i = 0; i < sets; i++) SetEntry(reps: 12, kg: 6)]),
    ],
  );
  final GlobalKey key = GlobalKey();
  await t.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
      home: SessionScreen(store: d.store, deps: d, rebuild: rebuildFor(d)),
    ),
  ));
  await t.pumpAndSettle();
  return (d, key);
}

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  tearDownAll(() => OG.fontFamily = null);

  testWidgets('a: main screen', (WidgetTester t) async {
    final (AppDeps _, GlobalKey key) = await _open(t);
    await _save(t, key, 'a');
  });

  testWidgets('b: Change plan sheet', (WidgetTester t) async {
    final (AppDeps _, GlobalKey key) = await _open(t);
    await t.tap(find.text('Change plan'));
    await t.pumpAndSettle();
    await _save(t, key, 'b');
  });

  testWidgets('c: Why this session sheet', (WidgetTester t) async {
    final FakeConvexClient fake = FakeConvexClient()
      ..planLoadAnswer = <String, int>{'shoulders': 3, 'forearms': 1, 'calves': 2, 'chest': 0};
    final (AppDeps _, GlobalKey key) = await _open(t, client: fake);
    await t.tap(find.byKey(const ValueKey<String>('why-icon')));
    await t.pumpAndSettle();
    expect(find.text(_why.split(' · ').last), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('why-figure')), findsOneWidget);
    await _save(t, key, 'c');
  });

  testWidgets('d: rep/kg exercise, set 1 done', (WidgetTester t) async {
    final (AppDeps d, GlobalKey key) = await _open(t, sets: 3);
    d.store.pickExercise(1);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('set-check-1-0')));
    await t.pumpAndSettle();
    await _save(t, key, 'd');
  });

  testWidgets('e: time exercise entry open', (WidgetTester t) async {
    final (AppDeps _, GlobalKey key) = await _open(t, sets: 3);
    await _save(t, key, 'e');
  });

  testWidgets('f: all sets done shows the bottom button', (WidgetTester t) async {
    final (AppDeps d, GlobalKey key) = await _open(t, sets: 3);
    d.store.pickExercise(1);
    await t.pumpAndSettle();
    for (int i = 0; i < 3; i++) {
      await t.tap(find.byKey(ValueKey<String>('set-check-1-$i')));
      await t.pumpAndSettle();
    }
    await _save(t, key, 'f');
  });

  testWidgets('g: leave sheet', (WidgetTester t) async {
    final (AppDeps d, GlobalKey key) = await _open(t, sets: 3);
    d.store.completeSet();
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.arrow_back));
    await t.pumpAndSettle();
    await _save(t, key, 'g');
  });
}
