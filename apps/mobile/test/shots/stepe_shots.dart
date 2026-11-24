// Visual proof of step E and G (ADR-032): the program chat is the shared chat
// with a program draft card, and the goal draft card shows labelled rows with
// no time line. Not part of the normal suite (no _test suffix).
// Run by path: flutter test test/shots/stepe_shots.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/chat_screen.dart';
import 'package:opengym/theme.dart';

import '../support/fake_convex_client.dart';
import '../support/load_fonts.dart';
import '../support/program_fixtures.dart';
import '../support/test_deps.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/stepE';

Future<void> _save(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image img = await b.toImage(pixelRatio: 3);
    final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_out).create(recursive: true);
    await File('$_out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

GlobalKey _view(WidgetTester t, double height) {
  t.view.physicalSize = Size(390 * 3, height * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  return GlobalKey();
}

Widget _app(GlobalKey key, Widget home) => RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
        home: home,
      ),
    );

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  tearDownAll(() => OG.fontFamily = null);

  testWidgets('1: the program chat with a program draft card', (WidgetTester t) async {
    final GlobalKey key = _view(t, 1900);
    final FakeConvexClient fake = FakeConvexClient();
    await fake.createThread(threadId: 'th', about: const ThreadAbout());
    final AppDeps d = await testDeps(fake);
    d.coach.start();
    await t.runAsync(_settle);
    await d.coach.openAboutProgram();
    await d.coach.send('Week 1: leg press 2x12, hamstring curl, wall sit. Bike twice. Left knee, skiing on 19 Dec.');
    fake.coachAnswers(
      'th',
      'A four week knee program, three kinds of day, built around the left knee. Agree if it fits.',
      proposalId: 'p1',
      actions: const <CoachAction>[
        CoachAction(actionId: 'a1', name: 'propose_program', status: 'drafted', detail: 'New program: being written'),
      ],
    );
    fake.setThreadProposals('th', <Proposal>[kneeProposal(id: 'p1')]);
    await t.pumpWidget(_app(key, ChatScreen(deps: d)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey<String>('proposal-agree')), findsOneWidget);
    await _save(t, key, '1-program-chat-draft-card');
  });

  testWidgets('2: the goal draft card, labelled rows and no time line', (WidgetTester t) async {
    final GlobalKey key = _view(t, 844);
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake);
    d.coach.start();
    await t.runAsync(_settle);
    await d.coach.openPart(
      context: const ChatContext(screen: 'goal'),
      line: 'New goal',
      hint: 'Say what you want to reach.',
      composerHint: 'Bench press 70 kg by spring',
    );
    await t.pumpWidget(_app(key, ChatScreen(deps: d, autofocus: true)));
    await t.pumpAndSettle();
    await d.coach.send('I want to bench press 70 kg by spring, training 3 times a week');
    fake.logDrafted(
      fake.serverThreads.keys.single,
      'Understood: a strength goal on Bench press. Check it, then press Done.',
      LogDraft(
        kind: 'Goal',
        summary: 'Bench press 70 kg by spring',
        at: DateTime.now().millisecondsSinceEpoch,
        goalRows: const <(String, String)>[('Exercise', 'Bench press'), ('Target', '70 kg'), ('Per week', '3')],
        noEntry: true,
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey<String>('log-draft-when')), findsNothing);
    await _save(t, key, '2-goal-draft-card');
  });
}
