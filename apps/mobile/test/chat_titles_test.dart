import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/screens/threads_screen.dart';

import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

/// Opens the thread list from a plain Home page, so Back has a route to pop to.
Future<(FakeConvexClient, AppDeps)> _open(WidgetTester t, {bool withThread = false}) async {
  t.view.physicalSize = const Size(400, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final FakeConvexClient fake = FakeConvexClient();
  if (withThread) {
    await fake.createThread(threadId: 'old', title: 'Squat progress');
  }
  final AppDeps deps = await testDeps(fake);
  deps.coach.start();
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (BuildContext c) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(c)
              .push(MaterialPageRoute<void>(builder: (BuildContext _) => ThreadsScreen(deps: deps))),
          child: const Text('Home'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('Home'));
  await t.pumpAndSettle();
  return (fake, deps);
}

Future<void> _type(WidgetTester t, String text) async {
  await t.enterText(find.byType(TextField), text);
  await t.pump();
  await t.tap(find.byIcon(Icons.arrow_upward));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('no threads: Chat opens a new empty chat, and Back goes Home, not to an empty list',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps deps) = await _open(t);
    expect(find.byType(TextField), findsOneWidget); // ready to type
    expect(find.text('New chat'), findsOneWidget);
    expect(find.text('No chats yet.'), findsNothing);
    expect(fake.calls.where((String c) => c.startsWith('createThread')), isEmpty); // nothing on the server yet
    expect(deps.coach.isDraft, isTrue);
    await t.tap(find.byIcon(Icons.chevron_left));
    await t.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(ThreadsScreen), findsNothing);
    expect(fake.serverThreads, isEmpty);
  });

  testWidgets('with threads the list shows as before', (WidgetTester t) async {
    await _open(t, withThread: true);
    expect(find.text('Squat progress'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a new thread asks for no name; the title follows the first message and then the AI title',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps deps) = await _open(t, withThread: true);
    await t.tap(find.text('New chat'));
    await t.pumpAndSettle();
    expect(find.text('Title'), findsNothing); // no name sheet
    expect(find.byType(TextField), findsOneWidget);

    await _type(t, 'i want to bench press more');
    expect(fake.serverThreads.length, 2);
    final String id = deps.coach.currentId!;
    expect(deps.coach.isDraft, isFalse);
    expect(find.text('I want to bench press more'), findsWidgets); // header and bubble
    expect(fake.serverThreads[id]!.titleSource, 'auto');

    fake.aiTitle(id, 'Bench press plan');
    await t.pumpAndSettle();
    expect(find.text('Bench press plan'), findsWidgets);
    expect(deps.coach.currentThread!.title, 'Bench press plan');
  });

  testWidgets('rename from the chat header; a later automatic title does not replace it', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps deps) = await _open(t);
    await _type(t, 'hello coach');
    final String id = deps.coach.currentId!;
    await t.tap(find.byKey(const ValueKey<String>('chat-title')));
    await t.pumpAndSettle();
    expect(find.text('Rename chat'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'My legs');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Rename chat'), findsNothing);
    expect(find.text('My legs'), findsWidgets);
    fake.aiTitle(id, 'Something else');
    await t.pumpAndSettle();
    expect(find.text('My legs'), findsWidgets);
    expect(fake.serverThreads[id]!.titleSource, 'user');
  });

  testWidgets('rename from the list row', (WidgetTester t) async {
    final (FakeConvexClient fake, _) = await _open(t, withThread: true);
    await t.tap(find.byKey(const ValueKey<String>('thread-rename')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Deadlifts');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Deadlifts'), findsOneWidget);
    expect(find.text('Squat progress'), findsNothing);
    expect(fake.serverThreads['old']!.titleSource, 'user');
  });

  testWidgets('a tap on the messages closes the keyboard; sending keeps it open', (WidgetTester t) async {
    await _open(t);
    EditableText field() => t.widget<EditableText>(find.byType(EditableText));
    await t.tap(find.byType(TextField));
    await t.pumpAndSettle();
    expect(field().focusNode.hasFocus, isTrue);
    await t.tapAt(const Offset(200, 300)); // the message area
    await t.pumpAndSettle();
    expect(field().focusNode.hasFocus, isFalse);

    await t.tap(find.byType(TextField));
    await t.enterText(find.byType(TextField), 'hi');
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pumpAndSettle();
    expect(field().focusNode.hasFocus, isTrue);
  });
}
