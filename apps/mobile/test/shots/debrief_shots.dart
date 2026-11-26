// Visual proof of the coach debrief (ADR-041). Not part of the normal suite
// (the file name has no _test suffix). Run by path:
//   flutter test test/shots/debrief_shots.dart
// It writes recap-debrief.png (the session recap: the coach's debrief with its
// question and three answers on top, then the body figure, then the sets) and
// debrief-chat.png (the debrief chat after the person tapped an answer).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_types.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_recap_screen.dart';
import 'package:opengym/theme.dart';

import '../support/fake_convex_client.dart';
import '../support/load_fonts.dart';
import '../support/test_deps.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/debrief';

Future<void> _save(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image img = await b.toImage(pixelRatio: 2);
    final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_out).create(recursive: true);
    await File('$_out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

final int _end = DateTime.now().millisecondsSinceEpoch - 2 * 3600000;

Session _session() => Session(
      id: 's1',
      kind: 'gym',
      type: 'Gym',
      focus: 'Legs',
      startedAt: _end - 38 * 60000,
      endedAt: _end,
      exercises: <Exercise>[
        Exercise(id: 'e1', name: 'Leg press', sets: <SetEntry>[
          SetEntry(reps: 12, kg: 50, done: true),
          SetEntry(reps: 12, kg: 55, done: true),
          SetEntry(reps: 10, kg: 60, done: true),
        ]),
        Exercise(id: 'e2', name: 'Calf raise', sets: <SetEntry>[SetEntry(reps: 15, kg: 30, done: true)]),
      ],
    );

const Review _review = Review(
  sessionId: 's1',
  source: 'ai',
  message: "Wow, that's a big jump on the leg press, 10 kg up in one go. Short one today though, and you skipped the squats. "
      'What happened?',
  question: CoachQuestion(text: 'How did the knee feel at 60 kg?', answers: <QuickAnswer>[
    QuickAnswer(id: 'a1', label: 'Fine'),
    QuickAnswer(id: 'a2', label: 'A bit sore'),
    QuickAnswer(id: 'a3', label: 'Pain'),
  ]),
);

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  tearDownAll(() => OG.fontFamily = null);

  Widget app(GlobalKey key, Widget home) => RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
          home: home,
        ),
      );

  testWidgets('recap with the debrief, then the chat after an answer', (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 2, 1250 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final GlobalKey key = GlobalKey();
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake, sessions: <Session>[_session()]);
    d.coach.start();
    fake.reviews['s1'] = Live<Stored<Review?>>()..set(const Stored<Review?>(_review, stored: true));
    fake.loads['s1'] = Live<Map<String, int>?>()..set(<String, int>{'quads': 3, 'glutes': 2, 'calves': 1});
    await t.pumpWidget(app(key, SessionRecapScreen(deps: d, sessionId: 's1')));
    await t.pump();
    await t.pump();
    await _save(t, key, 'recap-debrief');

    await t.tap(find.text('A bit sore'));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await t.pumpAndSettle();
    await _save(t, key, 'debrief-chat');
  });
}
