import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/chat_screen.dart';
import 'package:opengym/screens/program_chat.dart';
import 'package:opengym/screens/program_screen.dart';

import 'support/chat_fixtures.dart';
import 'support/fake_convex_client.dart';
import 'support/program_fixtures.dart';
import 'support/test_deps.dart';

Finder _key(String k) => find.byKey(ValueKey<String>(k));

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// A chat about a new program with one message of the person and one answer of
/// the coach that carries [proposal].
Future<(FakeConvexClient, AppDeps)> _chat(WidgetTester t, {List<Proposal>? proposals}) async {
  final FakeConvexClient fake = FakeConvexClient();
  await fake.createThread(threadId: 'th', about: const ThreadAbout());
  fake.serverChanged(() {});
  final AppDeps d = await testDeps(fake);
  d.coach.start();
  await d.coach.openAboutProgram();
  await t.runAsync(_settle);
  await d.coach.send('Prepare my knee for skiing');
  fake.coachAnswers('th', 'I will write a four week knee program.', proposalId: 'p1');
  fake.setThreadProposals('th', proposals ?? <Proposal>[kneeProposal(id: 'p1')]);
  t.view.physicalSize = const Size(390, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: ChatScreen(deps: d)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  return (fake, d);
}

void main() {
  group('the chat about a program (store)', () {
    test('a new program with no thread opens a draft; the first message creates it with about', () async {
      final FakeConvexClient fake = FakeConvexClient();
      final AppDeps d = await testDeps(fake);
      d.coach.start();
      await _settle();
      await d.coach.openAboutProgram();
      expect(d.coach.isDraft, isTrue);
      expect(d.coach.currentAbout, isNotNull);
      expect(d.coach.currentAbout!.id, isNull);
      expect(fake.serverThreads, isEmpty);
      await d.coach.send('a program for my knee');
      expect(fake.serverThreads.length, 1);
      final Thread t = fake.serverThreads.values.single;
      expect(t.about!.kind, 'program');
      expect(t.about!.id, isNull);
      expect(t.title, 'New program');
    });

    test('a thread of that program is reused, for a new program and for an existing one', () async {
      final FakeConvexClient fake = FakeConvexClient();
      await fake.createThread(threadId: 'new', about: const ThreadAbout());
      await fake.createThread(threadId: 'of-prog', about: const ThreadAbout(id: 'prog-1'));
      await fake.createThread(threadId: 'plain', title: 'Squats');
      final AppDeps d = await testDeps(fake);
      d.coach.start();
      await _settle();
      await d.coach.openAboutProgram();
      expect(d.coach.currentId, 'new');
      expect(d.coach.isDraft, isFalse);
      await d.coach.openAboutProgram(programId: 'prog-1');
      expect(d.coach.currentId, 'of-prog');
      await d.coach.openAboutProgram(programId: 'other');
      expect(d.coach.isDraft, isTrue);
      expect(d.coach.currentAbout!.id, 'other');
      expect(fake.serverThreads.length, 3);
    });

    test('the proposals of the open chat follow the server; the newest ready one is live', () async {
      final FakeConvexClient fake = FakeConvexClient();
      await fake.createThread(threadId: 'th', about: const ThreadAbout());
      final AppDeps d = await testDeps(fake);
      d.coach.start();
      await _settle();
      await d.coach.openAboutProgram();
      fake.setThreadProposals('th', <Proposal>[
        kneeProposal(id: 'p1'),
        kneeProposal(id: 'p2'),
        kneeProposal(id: 'p3', status: 'building'),
      ]);
      await _settle();
      expect(d.coach.proposals.length, 3);
      expect(d.coach.liveProposalId, 'p2');
      expect(d.coach.proposalById('p3')!.building, isTrue);
      expect(d.coach.proposalById('gone'), isNull);
    });

    test('an ordinary chat does not subscribe to proposals', () async {
      final FakeConvexClient fake = FakeConvexClient();
      await fake.createThread(threadId: 'plain', title: 'Squats');
      final AppDeps d = await testDeps(fake);
      d.coach.start();
      await _settle();
      await d.coach.openThread('plain');
      expect(fake.threadProposals, isEmpty);
    });

    test('the chat list hides chats that are about something until Show all chats', () async {
      final FakeConvexClient fake = FakeConvexClient();
      await fake.createThread(threadId: 'a', about: const ThreadAbout());
      await fake.createThread(threadId: 'b', title: 'Squats');
      final AppDeps d = await testDeps(fake);
      d.coach.start();
      await _settle();
      expect(d.coach.visibleThreads.map((Thread t) => t.id), <String>['b']);
      d.coach.setShowAllChats(true);
      expect(d.coach.visibleThreads.length, 2);
    });
  });

  group('the proposal in the chat', () {
    testWidgets('an empty new-program chat: its own hint and empty line, the same composer', (WidgetTester t) async {
      final FakeConvexClient fake = FakeConvexClient();
      final AppDeps d = await testDeps(fake);
      d.coach.start();
      await t.runAsync(_settle);
      await d.coach.openAboutProgram();
      await t.pumpWidget(MaterialApp(home: ChatScreen(deps: d)));
      await t.pumpAndSettle();
      expect(find.text('Paste a program, or say what you want'), findsOneWidget);
      expect(_key('chat-hint'), findsOneWidget);
      expect(_key('composer-plus'), findsOneWidget);
      expect(find.text('New program'), findsOneWidget);
    });

    testWidgets('a chat about an existing program asks for changes', (WidgetTester t) async {
      final FakeConvexClient fake = FakeConvexClient();
      final AppDeps d = await testDeps(fake);
      fake.programs.set(<Program>[kneeProgram()]);
      d.coach.start();
      await t.runAsync(_settle);
      await d.coach.openAboutProgram(programId: 'prog-1', title: 'Knee for skiing');
      await t.pumpWidget(MaterialApp(home: ChatScreen(deps: d)));
      await t.pumpAndSettle();
      expect(find.text('Ask, or say what should change'), findsOneWidget);
      expect(find.text('Knee for skiing'), findsOneWidget);
    });

    testWidgets('building: a compact busy card', (WidgetTester t) async {
      await _chat(t, proposals: <Proposal>[kneeProposal(id: 'p1', status: 'building')]);
      expect(find.text('The coach is writing the program. This can take a minute or two.'), findsOneWidget);
      expect(_key('proposal-agree'), findsNothing);
    });

    testWidgets('ready: the program with Agree and Cancel, and no feedback box', (WidgetTester t) async {
      await _chat(t);
      expect(find.text('I will write a four week knee program.'), findsOneWidget);
      expect(find.text('Knee for skiing'), findsWidgets);
      expect(_key('proposal-agree'), findsOneWidget);
      expect(_key('proposal-cancel'), findsOneWidget);
      expect(find.text('Change something'), findsNothing);
    });

    testWidgets('applied: one line Agreed with a link that opens the program', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await _chat(t, proposals: <Proposal>[kneeProposal(id: 'p1', status: 'applied')]);
      fake.programs.set(<Program>[kneeProgram()]);
      await fake.acceptProposal('p1');
      fake.serverChanged(() {
        final Thread th = fake.serverThreads['th']!;
        fake.serverThreads['th'] = Thread(
            id: th.id, title: th.title, createdAt: th.createdAt, updatedAt: th.updatedAt + 1, about: const ThreadAbout(id: 'prog-1'));
      });
      await t.pumpAndSettle();
      expect(find.text('Agreed'), findsOneWidget);
      expect(_key('proposal-agree'), findsNothing);
      await t.tap(find.text('Open program ›'));
      await t.pumpAndSettle();
      expect(find.byType(ProgramScreen), findsOneWidget);
      expect(d.coach.currentAbout!.id, 'prog-1');
    });

    testWidgets('declined: one muted line, no program body', (WidgetTester t) async {
      await _chat(t, proposals: <Proposal>[kneeProposal(id: 'p1', status: 'declined')]);
      expect(find.text('Replaced or cancelled'), findsOneWidget);
      expect(find.text('Session A'), findsNothing);
    });

    testWidgets('failed: the error text', (WidgetTester t) async {
      await _chat(t, proposals: <Proposal>[kneeProposal(id: 'p1', status: 'failed', error: 'The coach could not read the text.')]);
      expect(find.text('The coach could not read the text.'), findsOneWidget);
    });

    testWidgets('stale: asks the person to ask again', (WidgetTester t) async {
      await _chat(t, proposals: <Proposal>[kneeProposal(id: 'p1', status: 'stale')]);
      expect(find.text('The program changed. Ask again.'), findsOneWidget);
    });

    testWidgets('a proposal that is gone shows nothing', (WidgetTester t) async {
      await _chat(t, proposals: <Proposal>[]);
      expect(find.text('I will write a four week knee program.'), findsOneWidget);
      expect(_key('proposal-agree'), findsNothing);
      expect(find.text('Replaced or cancelled'), findsNothing);
    });

    testWidgets('only the newest ready proposal has buttons', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps _) = await _chat(t, proposals: <Proposal>[kneeProposal(id: 'p1')]);
      fake.coachAnswers('th', 'Two days a week then.', proposalId: 'p2');
      fake.setThreadProposals('th', <Proposal>[kneeProposal(id: 'p1'), kneeProposal(id: 'p2')]);
      await t.pumpAndSettle();
      expect(_key('proposal-agree'), findsOneWidget);
      expect(find.text('Replaced or cancelled'), findsOneWidget);
    });

    testWidgets('Agree saves the proposal and opens the Program screen', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps _) = await _chat(t);
      fake.programs.set(<Program>[kneeProgram()]);
      await t.ensureVisible(_key('proposal-agree'));
      await t.tap(_key('proposal-agree'));
      await t.pumpAndSettle();
      expect(fake.calls, contains('acceptProposal:p1'));
      expect(find.byType(ProgramScreen), findsOneWidget);
    });

    testWidgets('a refused Agree keeps the card and shows the reason', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps _) = await _chat(t);
      fake.acceptError = const ConvexCallException('The program changed.');
      await t.ensureVisible(_key('proposal-agree'));
      await t.tap(_key('proposal-agree'));
      await t.pumpAndSettle();
      expect(find.byType(ProgramScreen), findsNothing);
      expect(_key('proposal-agree'), findsOneWidget);
      expect(find.text('The program changed.'), findsOneWidget);
    });

    testWidgets('Cancel declines the proposal at once, without a confirm sheet', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps _) = await _chat(t);
      await t.ensureVisible(_key('proposal-cancel'));
      await t.tap(_key('proposal-cancel'));
      await t.pumpAndSettle();
      expect(fake.calls, contains('declineProposal:p1'));
    });
  });

  group('the chat list', () {
    testWidgets('hides chats about a program; Show all chats shows them with a label', (WidgetTester t) async {
      final FakeConvexClient fake = FakeConvexClient();
      await fake.createThread(threadId: 'a', title: 'Knee talk', about: const ThreadAbout());
      await fake.createThread(threadId: 'b', title: 'Squat progress');
      final AppDeps d = await testDeps(fake);
      await openChat(t, d);
      await t.tap(_key('chat-threads'));
      await t.pumpAndSettle();
      expect(find.text('Squat progress'), findsOneWidget);
      expect(find.text('Knee talk'), findsNothing);
      await t.tap(_key('show-all-chats'));
      await t.pumpAndSettle();
      expect(find.text('Knee talk'), findsOneWidget);
      expect(find.text('Program'), findsOneWidget);
      expect(d.coach.showAllChats, isTrue);
    });
  });

  testWidgets('openProgramChat opens the chat screen about that program', (WidgetTester t) async {
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake);
    d.coach.start();
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (BuildContext c) => TextButton(
          onPressed: () => openProgramChat(c, d, program: kneeProgram()),
          child: const Text('go'),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(d.coach.currentAbout!.id, 'prog-1');
  });
}
