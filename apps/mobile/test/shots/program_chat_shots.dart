// Visual proof of the program chat. Not part of the normal suite (the file
// name has no _test suffix). Run by path:
//   flutter test test/shots/program_chat_shots.dart
// It writes 1-empty-chat.png (an empty new-program chat), 2-proposal.png (a
// pasted text, the coach's line and a ready proposal card) and 3-chat-list.png
// (the chat list with "Show all chats" on) to the shots folder, at 390 px
// width, pixel ratio 3.
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

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/program-chat/app';

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

  testWidgets('1: an empty new-program chat', (WidgetTester t) async {
    final GlobalKey key = _view(t, 844);
    final AppDeps d = await testDeps(FakeConvexClient());
    d.coach.start();
    await t.runAsync(_settle);
    await d.coach.openAboutProgram();
    await t.pumpWidget(_app(key, ChatScreen(deps: d)));
    await t.pumpAndSettle();
    await _save(t, key, '1-empty-chat');
  });

  testWidgets('2: a pasted text, the coach line and a ready proposal', (WidgetTester t) async {
    final GlobalKey key = _view(t, 1900);
    final FakeConvexClient fake = FakeConvexClient();
    await fake.createThread(threadId: 'th', about: const ThreadAbout());
    final AppDeps d = await testDeps(fake);
    d.coach.start();
    await t.runAsync(_settle);
    await d.coach.openAboutProgram();
    await d.coach.send('Week 1: leg press 2x12, hamstring curl, wall sit. Bike twice. Left knee, skiing on 19 Dec.');
    fake.coachAnswers('th', 'A four week knee program, three kinds of day, built around the left knee. Agree if it fits.',
        proposalId: 'p1');
    fake.setThreadProposals('th', <Proposal>[kneeProposal(id: 'p1')]);
    await t.pumpWidget(_app(key, ChatScreen(deps: d)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey<String>('proposal-agree')), findsOneWidget);
    await _save(t, key, '2-proposal');
  });

  testWidgets('3: the chat list with Show all chats on', (WidgetTester t) async {
    final GlobalKey key = _view(t, 844);
    final FakeConvexClient fake = FakeConvexClient();
    await fake.createThread(threadId: 'a', title: 'Knee for skiing', about: const ThreadAbout(id: 'prog-1'));
    await fake.createThread(threadId: 'b', title: 'Squat progress');
    await fake.createThread(threadId: 'c', title: 'New program', about: const ThreadAbout());
    fake.coachAnswers('b', 'Your squat is up 5 kg since October.');
    fake.coachAnswers('a', 'Two days a week then.');
    final AppDeps d = await testDeps(fake);
    d.coach.start();
    await t.runAsync(_settle);
    d.coach.setShowAllChats(true);
    await d.coach.openThread('b');
    await t.pumpWidget(_app(key, ChatScreen(deps: d)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('chat-threads')));
    await t.pumpAndSettle();
    expect(find.text('Program'), findsNWidgets(2));
    await _save(t, key, '3-chat-list');
  });
}
