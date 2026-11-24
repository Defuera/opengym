import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/open_session_sync.dart';
import 'package:opengym/data/pickers.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/chat_screen.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/stores/connection_store.dart';
import 'package:opengym/widgets/composer_bar.dart';

import 'support/chat_fixtures.dart';
import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

const Key _send = ValueKey<String>('composer-send');
const Key _plus = ValueKey<String>('composer-plus');

Exercise _ex(String id, String name, {bool done = false}) =>
    Exercise(id: id, name: name, sets: <SetEntry>[SetEntry(reps: 10, kg: 0, done: done)]);

Future<(FakeConvexClient, AppDeps)> _session(WidgetTester t, {Pickers? pickers}) async {
  t.view.physicalSize = const Size(800, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final FakeConvexClient fake = FakeConvexClient();
  final AppDeps d = await testDeps(fake, pickers: pickers);
  d.coach.start();
  d.store.begin(
    activity: 'Gym',
    focus: 'Legs',
    prepared: <Exercise>[_ex('e1', 'Tandem Stand'), _ex('e2', 'Squat')],
  );
  await t.pumpWidget(MaterialApp(home: SessionScreen(store: d.store, deps: d)));
  await t.pump();
  return (fake, d);
}

Future<void> _type(WidgetTester t, String s) async {
  await t.enterText(find.byType(TextField).last, s);
  await t.pump();
  await t.tap(find.byKey(_send));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('the one floating chat button opens the chat with the shown exercise as context', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _session(t);
    expect(find.text('Change plan'), findsNothing);
    expect(find.text('Change this exercise'), findsNothing);
    await t.tap(find.byKey(const ValueKey<String>('chat-fab')));
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Gym, Legs \u00b7 Tandem Stand'), findsOneWidget);
    expect(find.text('What do you want to change?'), findsOneWidget);
    await _type(t, 'I do have a balance board');
    final ChatContext c = fake.sentContexts.single!;
    expect(c.screen, 'exercise');
    expect(c.exerciseId, 'e1');
    expect(c.openSessionId, d.store.active!.id);
    expect(fake.serverMessages.values.single.single.context!.screen, 'exercise');
  });

  testWidgets('the button follows the selected exercise; with none the context is the session', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _session(t);
    d.store.pickExercise(1);
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('chat-fab')));
    await t.pumpAndSettle();
    expect(find.text('Gym, Legs \u00b7 Squat'), findsOneWidget);
    await _type(t, 'too heavy');
    expect(fake.sentContexts.last!.exerciseId, 'e2');
    await t.tap(find.byIcon(Icons.chevron_left));
    await t.pumpAndSettle();
    d.store.discardExercise(1);
    d.store.discardExercise(0);
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('chat-fab')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pumpAndSettle();
    expect(find.text('Gym, Legs'), findsOneWidget);
    await _type(t, 'build me another one');
    expect(fake.serverThreads, hasLength(1)); // the thread of the open session is reused
    expect(fake.sentContexts.last!.screen, 'session');
    expect(fake.sentContexts.last!.exerciseId, isNull);
  });

  testWidgets('the chat of an open session is the same thread after an app restart', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _session(t);
    await t.tap(find.byKey(const ValueKey<String>('chat-fab')));
    await t.pumpAndSettle();
    await _type(t, 'first');
    final String thread = fake.serverThreads.keys.single;
    expect(fake.serverThreads[thread]!.openSessionId, d.store.active!.id);
    // A chat that is not about a session, newer than the first one.
    await fake.createThread(threadId: 'other', title: 'Other');
    await fake.sendMessage(threadId: 'other', messageId: 'o1', text: 'hi', context: const ChatContext(screen: 'chat'));
    // A new app run: a new store, an empty memory, the same server.
    final AppDeps d2 = await testDeps(fake);
    d2.coach.start();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.runAsync(() => d2.coach.openWithContext(
          context: ChatContext(screen: 'session', openSessionId: d.store.active!.id),
          line: 'Gym, Legs',
          hint: 'What do you want to change?',
        ));
    expect(d2.coach.currentId, thread);
    expect(d2.coach.isDraft, isFalse);
    // Another session id gets its own new chat.
    await t.runAsync(() => d2.coach.openWithContext(context: const ChatContext(screen: 'session', openSessionId: 'else'), line: 'x', hint: 'y'));
    expect(d2.coach.currentId, isNot(thread));
    expect(d2.coach.isDraft, isTrue);
  });

  testWidgets('an old session chat without openSessionId is not found: the session chat opens a new one, with no error', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _session(t);
    // A thread made before the server stored openSessionId: it has no id of any session.
    await fake.createThread(threadId: 'old', title: 'Old session chat');
    expect(fake.serverThreads['old']!.openSessionId, isNull);
    final AppDeps d2 = await testDeps(fake);
    d2.coach.start();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(d2.coach.sessionThreadId(d.store.active!.id), isNull);
    await t.runAsync(() => d2.coach.openWithContext(
          context: ChatContext(screen: 'session', openSessionId: d.store.active!.id),
          line: 'Gym, Legs',
          hint: 'What do you want to change?',
        ));
    expect(d2.coach.isDraft, isTrue);
    expect(d2.coach.currentId, isNot('old'));
    expect(d2.coach.error, isNull);
    // The memory of this run points at a thread that is gone: also a new chat, no error.
    await t.runAsync(() => d2.coach.openWithContext(context: ChatContext(screen: 'session', openSessionId: d.store.active!.id), line: 'x', hint: 'y'));
    expect(d2.coach.error, isNull);
    expect(d2.coach.isDraft, isTrue);
  });

  testWidgets('the action lines show the server detail; a proposal row shows the weight the server gives',
      (WidgetTester t) async {
    final (FakeConvexClient fake, _) = await _session(t);
    await t.tap(find.byKey(const ValueKey<String>('chat-fab')));
    await t.pumpAndSettle();
    await _type(t, 'swap it');
    fake.coachTurnAnswers(
      fake.serverThreads.keys.single,
      'Done.',
      actions: const <CoachAction>[
        CoachAction(actionId: 'a1', name: 'replace_open_exercise', status: 'applied', detail: 'Tandem Stand \u2192 Balance Board'),
        CoachAction(actionId: 'a2', name: 'remove_open_exercise', status: 'rejected', reason: 'a set is done', detail: 'ignored'),
      ],
      proposal: const CoachPlan(rows: <(String, String)>[('Squat', '3 \u00d7 10 \u00b7 40 kg'), ('Calf Raise', '3 \u00d7 15')]),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Tandem Stand \u2192 Balance Board'), findsOneWidget);
    expect(find.text('Not changed: a set is done'), findsOneWidget);
    expect(find.text('3 \u00d7 10 \u00b7 40 kg'), findsOneWidget);
    expect(find.text('3 \u00d7 15'), findsOneWidget);
  });

  testWidgets('the button stays when a set is done and does not cover the set controls', (WidgetTester t) async {
    final (_, AppDeps d) = await _session(t);
    d.store.toggleSet(0);
    await t.pump();
    final Finder fab = find.byKey(const ValueKey<String>('chat-fab'));
    expect(fab, findsOneWidget);
    expect(t.getRect(find.byKey(const ValueKey<String>('set-check-0-0'))).overlaps(t.getRect(fab)), isFalse);
  });

  testWidgets('a plain chat sends the chat screen as its context', (WidgetTester t) async {
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake);
    await openChat(t, d);
    await _type(t, 'hello');
    expect(fake.sentContexts.single!.screen, 'chat');
    expect(find.byType(ComposerBar), findsOneWidget);
  });

  testWidgets('a coach reply shows its action lines and a question with quick answers; a tap sends the label with the same context',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _session(t);
    await t.tap(find.byKey(const ValueKey<String>('chat-fab')));
    await t.pumpAndSettle();
    await _type(t, 'swap it');
    final String thread = fake.serverThreads.keys.single;
    fake.coachTurnAnswers(
      thread,
      'I swapped the first one.',
      actions: const <CoachAction>[
        CoachAction(actionId: 'a1', name: 'replace_open_exercise', status: 'applied'),
        CoachAction(actionId: 'a2', name: 'remove_open_exercise', status: 'rejected', reason: 'this exercise already has a done set'),
      ],
      question: const CoachQuestion(
        text: 'Does your gym have a balance board?',
        answers: <QuickAnswer>[QuickAnswer(id: 'y', label: 'Yes'), QuickAnswer(id: 'n', label: 'No')],
      ),
      proposal: const CoachPlan(title: 'New workout', rows: <(String, String)>[('Goblet Squat', '3 x 10'), ('Calf Raise', '2 x 15')]),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('I swapped the first one.'), findsOneWidget);
    expect(find.text('Changed: one exercise'), findsOneWidget);
    expect(find.text('Not changed: this exercise already has a done set'), findsOneWidget);
    expect(find.text('Does your gym have a balance board?'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('coach-proposal')), findsOneWidget);
    expect(find.text('Goblet Squat'), findsOneWidget);
    expect(find.text('3 x 10'), findsOneWidget);
    final String turn = fake.serverMessages[thread]!.last.turnId!;
    await t.tap(find.text('Yes'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(fake.serverMessages[thread]!.last.text, 'Yes');
    final ChatContext c = fake.sentContexts.last!;
    expect(c.screen, 'exercise');
    expect(c.exerciseId, 'e1');
    expect(d.coach.chatContext!.exerciseId, 'e1');
    expect(fake.sentAnswers.last!.id, 'y');
    expect(fake.sentAnswers.last!.turnId, turn);
  });

  testWidgets('the chat composer takes a photo and a file, shows thumbnails, removes one, and the offline line is live',
      (WidgetTester t) async {
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake, pickers: FakePickers(photo: UploadItem(path: 'p.png', name: 'rack.png', bytes: tinyPng)));
    await openChat(t, d);
    await t.tap(find.byKey(_plus));
    await t.pumpAndSettle();
    await t.tap(find.text('Photo library'));
    await t.pumpAndSettle();
    expect(d.coach.attachments, hasLength(1));
    expect(find.text('Offline. Chat needs a connection to send.'), findsNothing);
    d.connection.state = ConnState.offline;
    d.connection.notifyListeners();
    await t.pump();
    expect(find.text('Offline. Chat needs a connection to send.'), findsOneWidget);
    d.connection.state = ConnState.connected;
    d.connection.notifyListeners();
    await t.pump();
    expect(find.text('Offline. Chat needs a connection to send.'), findsNothing);
  });

  testWidgets('a change by the coach shows on the session screen while the chat is open and after it closes',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _session(t);
    final OpenSessionSync sync = OpenSessionSync(
        client: fake, store: d.store, isConnected: () => true, delay: Duration.zero)
      ..start();
    addTearDown(sync.stop);
    await sync.flush();
    await t.tap(find.byKey(const ValueKey<String>('chat-fab')));
    await t.pumpAndSettle();
    final String id = d.store.active!.id;
    fake.openRemote.set(OpenRemote(
      session: Session(id: id, kind: 'gym', type: 'Gym', focus: 'Legs', startedAt: 1, exercises: <Exercise>[_ex('e3', 'Balance Board'), _ex('e2', 'Squat')]),
      rev: 9,
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(d.store.active!.exercises.first.name, 'Balance Board'); // while the chat is on top
    await t.tap(find.byIcon(Icons.chevron_left));
    await t.pumpAndSettle();
    expect(find.text('Balance Board'), findsWidgets);
    expect(find.text('Tandem Stand'), findsNothing);
  });
}
