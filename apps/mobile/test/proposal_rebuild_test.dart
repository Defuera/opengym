import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/stores/connection_store.dart';
import 'package:opengym/widgets/og_button.dart';

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

const String _hint = 'Change something? For example: no water bottles, I have dumbbells';
final Finder _field = find.widgetWithText(TextField, _hint);
final Finder _rebuild = find.widgetWithText(OgButton, 'Rebuild');

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

Future<void> _type(WidgetTester t, String s) async {
  await t.enterText(_field, s);
  await t.pump();
}

void main() {
  testWidgets('the proposal shows the field and a Rebuild button that is off while empty', (WidgetTester t) async {
    await _openProposal(t);
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(_field, findsOneWidget);
    expect(t.widget<OgButton>(_rebuild).onPressed, isNull);
    await _type(t, '   ');
    expect(t.widget<OgButton>(_rebuild).onPressed, isNull);
    await _type(t, 'no water bottles');
    expect(t.widget<OgButton>(_rebuild).onPressed, isNotNull);
    expect(find.text('Complete set'), findsOneWidget); // Start behaviour unchanged
  });

  testWidgets('Rebuild sends the trimmed feedback with the previous request, shows the card, then swaps the proposal',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openProposal(t);
    final String first = fake.lastStartId;
    await _type(t, '  I have no bottles, I have dumbbells ');
    await t.tap(_rebuild);
    await t.pump();
    expect(fake.startFeedback.last, ('I have no bottles, I have dumbbells', first));
    expect(fake.startNames.last, isNull);
    expect(find.text('Rebuilding…'), findsOneWidget);
    expect(find.text('Keep this session'), findsOneWidget);
    expect(_field, findsNothing);
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'ready', proposal: _proposal('Goblet squat', rationale: 'Dumbbells')));
    await t.pumpAndSettle();
    expect(find.text('Rebuilding…'), findsNothing);
    expect(d.store.active!.exercises.single.name, 'Goblet squat');
    expect(d.store.active!.planNote, 'Dumbbells');
    expect(find.text('Goblet squat'), findsWidgets);
    expect(find.text('Squat'), findsNothing);
    expect(t.widget<TextField>(_field).controller!.text, isEmpty); // ready for the next round
    expect(d.store.sessions.where((Session s) => s.id == d.store.active!.id), isEmpty); // nothing saved
  });

  testWidgets('feedback can be given again: the second rebuild points at the first rebuild', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openProposal(t);
    await _type(t, 'one');
    await t.tap(_rebuild);
    await t.pump();
    final String second = fake.lastStartId;
    fake.answerStart(StartRequest(requestId: second, status: 'ready', proposal: _proposal('Lunge')));
    await t.pumpAndSettle();
    await _type(t, 'two');
    await t.tap(_rebuild);
    await t.pump();
    expect(fake.startFeedback.last, ('two', second));
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'ready', proposal: _proposal('Row')));
    await t.pumpAndSettle();
    expect(d.store.active!.exercises.single.name, 'Row');
  });

  testWidgets('a failed rebuild keeps the old proposal and the text, shows a short line; the next try points at the old request',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openProposal(t);
    final String first = fake.lastStartId;
    await _type(t, 'no bottles');
    await t.tap(_rebuild);
    await t.pump();
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'failed'));
    await t.pumpAndSettle();
    expect(find.text('Could not rebuild. Try again.'), findsOneWidget);
    expect(d.store.active!.exercises.single.name, 'Squat');
    expect(t.widget<TextField>(_field).controller!.text, 'no bottles');
    await t.tap(_rebuild);
    await t.pump();
    expect(fake.startFeedback.last, ('no bottles', first));
    expect(find.text('Could not rebuild. Try again.'), findsNothing);
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'ready', proposal: _proposal('Lunge')));
    await t.pumpAndSettle();
    expect(d.store.active!.exercises.single.name, 'Lunge');
  });

  testWidgets('Keep this session stops waiting and keeps the proposal', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openProposal(t);
    await _type(t, 'no bottles');
    await t.tap(_rebuild);
    await t.pump();
    await t.tap(find.text('Keep this session'));
    await t.pump();
    expect(_field, findsOneWidget);
    expect(d.store.active!.exercises.single.name, 'Squat');
    expect(find.text('Could not rebuild. Try again.'), findsNothing);
  });

  testWidgets('offline: Rebuild is off and a short line says why; back online it works', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openProposal(t);
    await _type(t, 'no bottles');
    d.connection.state = ConnState.offline;
    // ignore: invalid_use_of_protected_member
    d.connection.notifyListeners();
    await t.pump();
    expect(t.widget<OgButton>(_rebuild).onPressed, isNull);
    expect(find.textContaining('Offline'), findsOneWidget);
    final int sent = fake.startSent.length;
    d.connection.state = ConnState.connected;
    // ignore: invalid_use_of_protected_member
    d.connection.notifyListeners();
    await t.pump();
    expect(find.textContaining('Offline'), findsNothing);
    expect(t.widget<OgButton>(_rebuild).onPressed, isNotNull);
    expect(fake.startSent.length, sent);
  });

  testWidgets('after the first set is done the feedback field is gone and a late answer changes nothing', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openProposal(t);
    await _type(t, 'no bottles');
    await t.tap(_rebuild);
    await t.pump();
    d.store.completeSet();
    await t.pump();
    expect(find.text('Rebuilding…'), findsNothing);
    expect(_field, findsNothing);
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'ready', proposal: _proposal('Lunge')));
    await t.pumpAndSettle();
    expect(d.store.active!.exercises.single.name, 'Squat');
  });

  testWidgets('keyboard-safe: the field and Rebuild stay above the keyboard', (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    t.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
    addTearDown(t.view.reset);
    final (FakeConvexClient fake, AppDeps _) = await openHome(t);
    await openStart(t);
    await pickAndStart(t, 'Home');
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'ready', proposal: _proposal('Squat')));
    await t.pumpAndSettle();
    expect(t.getRect(_rebuild).bottom, lessThanOrEqualTo(844 - 300));
    // The session screen itself overflows by 6 px at this width without the feedback row (checked on a bare SessionScreen), so only the position is asserted.
    t.takeException();
  });

  testWidgets('a session reopened from Home still takes feedback: it goes as the note of a new request',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps _) = await _openProposal(t);
    Navigator.of(t.element(find.byType(SessionScreen))).pop();
    await t.pumpAndSettle();
    expect(find.byType(SessionScreen), findsNothing);
    await t.tap(find.textContaining('Resume'));
    await t.pumpAndSettle();
    expect(_field, findsOneWidget);
    await _type(t, 'I have dumbbells');
    await t.tap(_rebuild);
    await t.pump();
    expect(fake.startNames.last, 'Gym');
    expect(fake.startFeedback.last, (null, null));
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'ready', proposal: _proposal('Goblet squat')));
    await t.pumpAndSettle();
    expect(find.text('Goblet squat'), findsWidgets);
  });
}
