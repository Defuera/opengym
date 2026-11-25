import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/data/outbox.dart';
import 'package:opengym/data/upload_item.dart';
import 'package:opengym/models.dart';
import 'package:opengym/stores/coach_store.dart';

import 'support/chat_fixtures.dart';
import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

const ValueKey<String> _send = ValueKey<String>('composer-send');
const ValueKey<String> _retry = ValueKey<String>('delivery-retry');

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

bool _fieldOn(WidgetTester t) => t.widget<TextField>(find.byType(TextField)).enabled ?? true;

void main() {
  group('the composer is never off for the link, a loading thread or a coach reply', () {
    testWidgets('offline: field, plus, camera and send stay on; a quiet line says what happens', (WidgetTester t) async {
      final FakeConvexClient fake = FakeConvexClient();
      final AppDeps d = await testDeps(fake, connected: false);
      await openChat(t, d);
      expect(_fieldOn(t), isTrue);
      expect(find.text('Offline. Messages are sent when the connection is back.'), findsOneWidget);
      expect(find.text('Offline. Chat needs a connection to send.'), findsNothing);
      await t.enterText(find.byType(TextField), 'hello');
      await t.pump();
      await t.tap(find.byKey(_send));
      await _settle(t);
      expect(find.text('hello'), findsOneWidget); // in the thread at once
      expect(find.text('Not sent'), findsOneWidget);
      expect(find.byKey(_retry), findsOneWidget);
      expect(fake.calls, isEmpty);
      expect(_fieldOn(t), isTrue);
    });

    testWidgets('while the thread history loads', (WidgetTester t) async {
      final FakeConvexClient fake = FakeConvexClient();
      final AppDeps d = await testDeps(fake);
      await openChat(t, d);
      d.coach.loadingMessages = true;
      d.coach.notifyListeners();
      await t.pump();
      expect(_fieldOn(t), isTrue);
      await t.enterText(find.byType(TextField), 'while loading');
      await t.pump();
      await t.tap(find.byKey(_send));
      await _settle(t);
      expect(fake.serverMessages.values.single.single.text, 'while loading');
    });

    testWidgets('while the coach is thinking, and while a message is still going out', (WidgetTester t) async {
      final FakeConvexClient fake = FakeConvexClient();
      final AppDeps d = await testDeps(fake);
      await openChat(t, d);
      fake.sendGate = Completer<void>();
      await t.enterText(find.byType(TextField), 'first');
      await t.pump();
      await t.tap(find.byKey(_send));
      await t.pump();
      expect(find.text('Sending…'), findsOneWidget);
      expect(_fieldOn(t), isTrue);
      await t.enterText(find.byType(TextField), 'second');
      await t.pump();
      await t.tap(find.byKey(_send));
      await t.pump();
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
      fake.sendGate!.complete();
      fake.sendGate = null;
      await _settle(t);
      final List<Message> sent = fake.serverMessages.values.single;
      expect(sent.map((Message m) => m.text), <String>['first', 'second']); // in order
      expect(_fieldOn(t), isTrue); // the coach is now thinking
      expect(d.coach.thinking, isTrue);
      await t.enterText(find.byType(TextField), 'third');
      await t.pump();
      await t.tap(find.byKey(_send));
      await _settle(t);
      expect(fake.serverMessages.values.single.map((Message m) => m.text), <String>['first', 'second', 'third']);
    });
  });

  group('store: the outbox carries chat messages', () {
    late FakeConvexClient fake;
    late bool on;
    late InMemoryOutboxRepository repo;

    Future<AppDeps> deps() => testDeps(fake, link: () => on, outboxRepo: repo);

    setUp(() {
      fake = FakeConvexClient();
      on = true;
      repo = InMemoryOutboxRepository();
    });

    test('offline: a new chat and its messages are kept, and go out once, in order, when the link is back', () async {
      final AppDeps d = await deps();
      d.coach.start();
      on = false;
      await d.coach.startNewChat();
      await d.coach.send('one');
      await d.coach.send('two');
      await pump();
      expect(d.coach.messages.map((Message m) => m.text), <String>['one', 'two']);
      expect(d.coach.messages.map((Message m) => d.coach.delivery(m.id)), everyElement(ChatDelivery.notSent));
      expect(fake.calls, isEmpty);
      expect(d.coach.visibleThreads.single.title, 'one'); // the chat is listed while it is not on the server

      on = true;
      await d.outbox.flush();
      await pump();
      expect(fake.calls.map((String c) => c.split(':').first), <String>['createThread', 'sendMessage', 'sendMessage']);
      final String thread = fake.serverThreads.keys.single;
      expect(fake.serverMessages[thread]!.map((Message m) => m.text), <String>['one', 'two']);
      expect(d.coach.messages, hasLength(2));
      expect(d.coach.messages.map((Message m) => d.coach.delivery(m.id)), everyElement(isNull));
      await d.outbox.flush();
      expect(fake.calls, hasLength(3)); // nothing is sent twice
    });

    test('a restart keeps the unsent messages, and the same message id goes out', () async {
      final AppDeps first = await deps();
      first.coach.start();
      on = false;
      await first.coach.startNewChat();
      await first.coach.send('kept');
      await pump();
      final String id = first.coach.messages.single.id;
      final String threadId = first.coach.currentId!;

      // A new run: new outbox and store on the same disk.
      final AppDeps second = await deps();
      await second.outbox.load();
      second.coach.start();
      await second.coach.openThread(threadId);
      await pump();
      expect(second.coach.messages.single.text, 'kept');
      expect(second.coach.messages.single.id, id);
      expect(second.coach.delivery(id), ChatDelivery.notSent);

      on = true;
      await second.outbox.flush();
      await pump();
      expect(fake.calls, contains('sendMessage:$id'));
      expect(fake.serverMessages[threadId]!.single.id, id);
    });

    test('Try again keeps the message id and the text; the server stores it once', () async {
      final AppDeps d = await deps();
      d.coach.start();
      await d.coach.startNewChat();
      fake.failNext = const ConvexCallException.unreachable(); // the thread call fails
      await d.coach.send('again');
      await pump();
      final String id = d.coach.messages.single.id;
      expect(d.coach.delivery(id), ChatDelivery.notSent);
      expect(d.coach.messages.single.text, 'again');
      await d.coach.retryMessage(id);
      await pump();
      await d.coach.retryMessage(id); // a second press changes nothing
      await pump();
      final String thread = fake.serverThreads.keys.single;
      expect(fake.serverMessages[thread]!.single.id, id);
      expect(d.coach.delivery(id), isNull);
    });

    test('a refusal by the server keeps the message as not sent with its text', () async {
      final AppDeps d = await deps();
      d.coach.start();
      await d.coach.startNewChat();
      fake.failNext = const ConvexCallException('message: too long', kind: ConvexFailure.rejected);
      await d.coach.send('long');
      await pump();
      final String id = d.coach.messages.single.id;
      expect(d.coach.delivery(id), ChatDelivery.notSent);
      expect(d.outbox.parkedCount, 1);
      await d.coach.retryMessage(id);
      await pump();
      expect(d.coach.delivery(id), isNull);
    });

    test('attachments wait with the message; the upload runs on retry', () async {
      final AppDeps d = await deps();
      d.coach.start();
      await d.coach.startNewChat();
      on = false;
      d.coach.addAttachment(const UploadItem(path: '', name: 'p.png', bytes: <int>[1, 2, 3]));
      await d.coach.send('see');
      await pump();
      expect(fake.calls, isEmpty);
      expect(d.coach.messages.single.fileIds, hasLength(1));
      on = true;
      await d.coach.retryMessage(d.coach.messages.single.id);
      await pump();
      expect(fake.calls.map((String c) => c.split(':').first), <String>['createThread', 'uploadFile', 'sendMessage']);
    });

    test('a quick answer sent offline is queued with its answer', () async {
      final AppDeps d = await deps();
      d.coach.start();
      final String? id = await d.coach.createThread('T');
      await d.coach.openThread(id!);
      await pump();
      on = false;
      expect(await d.coach.send('Approve', answer: const ChatAnswer(turnId: 'turn-1', id: 'approve')), isTrue);
      await pump();
      expect(d.coach.delivery(d.coach.messages.single.id), ChatDelivery.notSent);
      on = true;
      await d.outbox.flush();
      await pump();
      expect(fake.sentAnswers.single!.id, 'approve');
      expect(fake.sentAnswers.single!.turnId, 'turn-1');
    });

    test('deleting a thread drops its waiting messages', () async {
      final AppDeps d = await deps();
      d.coach.start();
      final String? id = await d.coach.createThread('T');
      await d.coach.openThread(id!);
      await pump();
      on = false;
      await d.coach.send('x');
      await pump();
      on = true;
      await d.coach.deleteThread(id);
      await pump();
      expect(d.outbox.chats, isEmpty);
    });
  });

  test('CoachStore still works on its own, without an outbox', () async {
    final FakeConvexClient fake = FakeConvexClient();
    final CoachStore coach = CoachStore(client: fake, isConnected: () => true)..start();
    await coach.startNewChat();
    expect(await coach.send('hi'), isTrue);
    await pump();
    expect(fake.serverMessages.values.single.single.text, 'hi');
  });
}
