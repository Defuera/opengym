import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_screen.dart';

import 'support/fake_convex_client.dart';
import 'support/sheet_fixtures.dart';

StartProposal _proposal(String exercise, {String rationale = 'Legs are due'}) => StartProposal(
      kind: 'gym',
      type: 'Gym',
      focus: 'Legs',
      plan: Plan(
        id: 'x',
        focus: 'Legs',
        createdAt: 1,
        source: 'ai',
        rationale: rationale,
        exercises: <PlanExercise>[
          PlanExercise(name: exercise, sets: const <PlanSet>[PlanSet(reps: 8, kg: 60)]),
        ],
      ),
    );


/// Home, Start, Gym, and the first proposal is on the session screen.
Future<(FakeConvexClient, AppDeps)> _openProposal(WidgetTester t, {bool connected = true}) async {
  t.view.physicalSize = const Size(800, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final (FakeConvexClient fake, AppDeps d) = await openHome(t, connected: connected);
  await openStart(t);
  await pickAndStart(t, 'Gym');
  fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'ready', proposal: _proposal('Squat')));
  await t.pumpAndSettle();
  return (fake, d);
}

void main() {
  testWidgets('back asks; Pause goes Home with the session unchanged; Resume reopens it', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await _openProposal(t);
    d.store.completeSet();
    await t.pump();
    final String id = d.store.active!.id;
    await t.tap(find.byIcon(Icons.arrow_back));
    await t.pumpAndSettle();
    expect(find.text('Leave this session?'), findsOneWidget);
    await t.tap(find.text('Pause, come back later'));
    await t.pumpAndSettle();
    expect(find.byType(SessionScreen), findsNothing);
    expect(d.store.active!.id, id);
    expect(d.store.hasDoneSet, isTrue);
    await t.tap(find.textContaining('Resume'));
    await t.pumpAndSettle();
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(d.store.active!.exercises.single.sets.first.done, isTrue);
    expect(find.text('End session'), findsNothing);
  });

  testWidgets('Finish is offered only with a done set; Discard removes the session', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await _openProposal(t);
    await t.tap(find.byIcon(Icons.arrow_back));
    await t.pumpAndSettle();
    expect(find.text('Finish and save'), findsNothing);
    expect(find.text('Discard session'), findsOneWidget);
    await t.tap(find.text('Discard session'));
    await t.pumpAndSettle();
    expect(find.text('Discard this session?'), findsOneWidget);
    expect(d.store.active, isNotNull);
    await t.tap(find.byKey(const ValueKey<String>('confirm-delete')));
    await t.pumpAndSettle();
    expect(d.store.active, isNull);
    expect(find.byType(SessionScreen), findsNothing);
  });

  testWidgets('Discard asks first: Keep it and closing the sheet keep the session', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await _openProposal(t);
    await t.tap(find.byIcon(Icons.arrow_back));
    await t.pumpAndSettle();
    await t.tap(find.text('Discard session'));
    await t.pumpAndSettle();
    await t.tap(find.text('Keep it'));
    await t.pumpAndSettle();
    expect(d.store.active, isNotNull);
    expect(find.byType(SessionScreen), findsOneWidget);
    await t.tap(find.byIcon(Icons.arrow_back));
    await t.pumpAndSettle();
    await t.tap(find.text('Discard session'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('og-sheet-close')));
    await t.pumpAndSettle();
    expect(d.store.active, isNotNull);
    expect(find.byType(SessionScreen), findsOneWidget);
  });

  testWidgets('the cross on an exercise chip asks first', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await _openProposal(t);
    d.store.addExercise('Bench');
    await t.pump();
    expect(d.store.active!.exercises.length, 2);
    await t.tap(find.byIcon(Icons.close).first);
    await t.pumpAndSettle();
    expect(find.text('Remove this exercise?'), findsOneWidget);
    await t.tap(find.text('Keep it'));
    await t.pumpAndSettle();
    expect(d.store.active!.exercises.length, 2);
    await t.tap(find.byIcon(Icons.close).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('og-sheet-close')));
    await t.pumpAndSettle();
    expect(d.store.active!.exercises.length, 2);
    await t.tap(find.byIcon(Icons.close).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('confirm-delete')));
    await t.pumpAndSettle();
    expect(d.store.active!.exercises.length, 1);
  });

  testWidgets('Finish and save ends the session when a set is done', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await _openProposal(t);
    d.store.completeSet();
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_back));
    await t.pumpAndSettle();
    await t.tap(find.text('Finish and save'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('confirm-finish')));
    await t.pumpAndSettle();
    expect(d.store.active, isNull);
    expect(d.store.sessions, isNotEmpty);
  });

  testWidgets('finishing asks first: "Keep going" and closing the sheet keep the session open', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await _openProposal(t);
    final int before = d.store.sessions.length;
    d.store.completeSet();
    await t.pump();
    for (final Finder dismiss in <Finder>[find.text('Keep going'), find.byKey(const ValueKey<String>('og-sheet-close'))]) {
      await t.tap(find.text('Finish session'));
      await t.pumpAndSettle();
      expect(find.text('Finish this session?'), findsOneWidget);
      expect(find.text('Every set is done.'), findsOneWidget);
      await t.tap(dismiss);
      await t.pumpAndSettle();
      expect(d.store.active, isNotNull);
      expect(d.store.sessions.length, before);
    }
    d.store.addSet();
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_back));
    await t.pumpAndSettle();
    await t.tap(find.text('Finish and save'));
    await t.pumpAndSettle();
    expect(find.text('1 set is not done. It is not saved.'), findsOneWidget);
  });

  testWidgets('closing the sheet stays; system back opens it', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await _openProposal(t);
    await t.tap(find.byIcon(Icons.arrow_back));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('og-sheet-close')));
    await t.pumpAndSettle();
    expect(find.text('Leave this session?'), findsNothing);
    expect(find.byType(SessionScreen), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Leave this session?'), findsOneWidget);
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(d.store.active, isNotNull);
  });
}
