// Visual proof of the one chat (ADR-032). Not part of the normal suite (the
// file name has no _test suffix). Run by path:
//   flutter test test/shots/onechat_shots.dart
// It writes 1-session.png (the session screen with the floating chat button)
// and 2-chat-session.png (the chat opened from it, with a reply that has two
// action lines, a whole-workout proposal and Approve / Change something
// buttons) at 390 px width, pixel ratio 3.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/theme.dart';

import '../support/fake_convex_client.dart';
import '../support/load_fonts.dart';
import '../support/test_deps.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/onechat';

Future<void> _save(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image img = await b.toImage(pixelRatio: 3);
    final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_out).create(recursive: true);
    await File('$_out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Exercise _ex(String id, String name) =>
    Exercise(id: id, name: name, sets: <SetEntry>[SetEntry(reps: 10, kg: 0), SetEntry(reps: 10, kg: 0)]);

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  tearDownAll(() => OG.fontFamily = null);

  testWidgets('1 and 2: the session screen, then the chat from an exercise', (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final GlobalKey key = GlobalKey();
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake);
    d.coach.start();
    d.store.begin(
      activity: 'Gym',
      focus: 'Legs',
      rationale: 'Legs are due.',
      prepared: <Exercise>[_ex('e1', 'Tandem Stand'), _ex('e2', 'Goblet Squat'), _ex('e3', 'Calf Raise')],
    );
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
        home: SessionScreen(store: d.store, deps: d),
      ),
    ));
    await t.pump();
    await _save(t, key, '1-session');

    await t.tap(find.byKey(const ValueKey<String>('chat-fab')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'I want to change the whole workout');
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('composer-send')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    fake.coachTurnAnswers(
      fake.serverThreads.keys.single,
      'Got it. I swapped Tandem Stand for a floor version and noted what your gym has.',
      actions: const <CoachAction>[
        CoachAction(actionId: 'a1', name: 'replace_open_exercise', status: 'applied'),
        CoachAction(actionId: 'a2', name: 'update_place', status: 'applied'),
      ],
      question: const CoachQuestion(
        text: 'Do you approve this workout?',
        answers: <QuickAnswer>[QuickAnswer(id: 'approve', label: 'Approve'), QuickAnswer(id: 'change', label: 'Change something')],
      ),
      proposal: const CoachPlan(title: 'Proposed workout', rows: <(String, String)>[
        ('Goblet Squat', '3 x 10'),
        ('Floor Tandem Stand', '2 x 30 s'),
        ('Calf Raise', '3 x 15'),
      ]),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    await _save(t, key, '2-chat-session');
  });
}
