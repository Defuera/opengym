import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/chat_screen.dart';
import 'package:opengym/screens/goals_screen.dart';

import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

/// ADR-032, step D: goals, limits and notes are drafted in the one chat.
const Key _send = ValueKey<String>('composer-send');

const LogDraft _goal = LogDraft(
  kind: 'Goal',
  summary: 'Bench press 70 kg by spring',
  at: 1700000000000,
  goal: 'Bench press 70 kg by spring, 70 kg',
  noEntry: true,
);

Future<(FakeConvexClient, AppDeps)> _goals(WidgetTester t) async {
  t.view.physicalSize = const Size(800, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final FakeConvexClient fake = FakeConvexClient();
  await fake.createGoal(goalId: 'g1', title: 'Squat 100 kg', kind: 'strength', targetKg: 100);
  final AppDeps d = await testDeps(fake);
  d.coach.start();
  d.goals.start();
  await t.pumpWidget(MaterialApp(home: GoalsScreen(deps: d)));
  await t.pumpAndSettle();
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
  testWidgets('Add goal opens the one chat with screen goal, a hint in the composer, and no form', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _goals(t);
    await t.tap(find.text('Add goal'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('New goal'), findsOneWidget);
    expect(find.text('Bench press 70 kg by spring'), findsOneWidget); // the composer hint
    expect(find.text('What do you want?'), findsNothing); // the old form is gone
    expect(find.byKey(const ValueKey<String>('composer-camera')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('composer-plus')), findsOneWidget);
    expect(d.coach.chatContext?.screen, 'goal');
    await _type(t, 'bench 70 kg');
    expect(fake.sentContexts.single!.screen, 'goal');
    expect(fake.sentContexts.single!.goalId, isNull);
  });

  testWidgets('a tap on a goal opens the chat for that goal; the draft card says Change goal; Done is sent and ends with Close only', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _goals(t);
    await t.tap(find.text('Squat 100 kg'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pumpAndSettle();
    expect(d.coach.chatContext?.goalId, 'g1');
    expect(find.text('Goal · Squat 100 kg'), findsOneWidget);
    await _type(t, 'make it 110');
    expect(fake.sentContexts.single!.goalId, 'g1');
    final String thread = fake.serverThreads.keys.single;
    fake.logDrafted(
      thread,
      'Here is the new goal.',
      const LogDraft(kind: 'Goal', summary: 'Squat 110 kg', at: 1700000000000, goal: 'Squat 110 kg, 110 kg', noEntry: true, changes: true),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Change goal'), findsOneWidget);
    expect(find.text('Squat 110 kg, 110 kg'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Add or change'), findsOneWidget);
    await t.tap(find.text('Done'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(fake.sentAnswers.last!.id, 'approve');
    expect(fake.sentContexts.last!.screen, 'goal');
    fake.logDrafted(thread, 'x', const LogDraft(kind: 'Goal', summary: 'Squat 110 kg', at: 1700000000000, goal: 'Squat 110 kg', noEntry: true, changes: true, state: 'applied'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Saved'), findsWidgets);
    expect(find.byKey(const ValueKey<String>('log-close')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('log-open')), findsNothing);
  });

  testWidgets('a new goal draft says New goal', (WidgetTester t) async {
    final (FakeConvexClient fake, _) = await _goals(t);
    await t.tap(find.text('Add goal'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pumpAndSettle();
    await _type(t, 'bench 70');
    fake.logDrafted(fake.serverThreads.keys.single, 'Draft.', _goal);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('New goal'), findsWidgets);
    expect(find.text('Bench press 70 kg by spring, 70 kg'), findsOneWidget);
  });

  test('the chat context carries the goal, limit, note and part to the server', () {
    const ChatContext c = ChatContext(screen: 'limit', limitId: 'l1', part: 'left_knee');
    expect(c.toJson(), <String, dynamic>{'screen': 'limit', 'limitId': 'l1', 'part': 'left_knee'});
    expect(ChatContext.fromJson(c.toJson())!.part, 'left_knee');
    expect(const ChatContext(screen: 'note', noteId: 'n1').toJson()['noteId'], 'n1');
  });

  test('a draft made outside the log chat is read with noEntry and changes', () {
    final LogDraft? d = LogDraft.fromJson(<String, dynamic>{
      'type': 'log',
      'kind': 'Limit',
      'summary': 'Left knee',
      'at': 1,
      'noEntry': true,
      'edits': <String, dynamic>{'limitId': 'l1'},
      'limit': <String, dynamic>{'part': 'left_knee', 'title': 'Left knee', 'rules': <Object>[]},
      'state': 'open',
    });
    expect(d!.noEntry, isTrue);
    expect(d.changes, isTrue);
    expect(d.kindLabel, 'Change limit');
    expect(d.limit, 'left_knee: Left knee');
  });
}
