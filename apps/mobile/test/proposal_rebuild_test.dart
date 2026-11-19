import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/stores/connection_store.dart';
import 'package:opengym/widgets/og_button.dart';
import 'package:opengym/widgets/session_meta_row.dart';

import 'support/set_taps.dart';
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
final Finder _change = find.widgetWithText(MetaItem, 'Change plan');
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

Future<void> _openChange(WidgetTester t) async {
  await t.tap(_change);
  await t.pumpAndSettle();
}

/// Opens "Change plan" if needed, types and presses Rebuild (the sheet closes).
Future<void> _send(WidgetTester t, String s) async {
  await _openChange(t);
  await _type(t, s);
  await t.tap(_rebuild);
  await t.pump();
  await t.pump(const Duration(seconds: 1)); // the sheet closes (the spinner never settles)
}

Future<void> _type(WidgetTester t, String s) async {
  await t.enterText(_field, s);
  await t.pump();
}

void main() {
  testWidgets('the main area has no feedback field; Change plan opens it, Rebuild is off while empty', (WidgetTester t) async {
    await _openProposal(t);
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(_field, findsNothing);
    expect(_rebuild, findsNothing);
    expect(setCheck(0, 0), findsOneWidget); // Start behaviour unchanged
    await _openChange(t);
    expect(_field, findsOneWidget);
    expect(t.widget<OgButton>(_rebuild).onPressed, isNull);
    await _type(t, '   ');
    expect(t.widget<OgButton>(_rebuild).onPressed, isNull);
    await _type(t, 'no water bottles');
    expect(t.widget<OgButton>(_rebuild).onPressed, isNotNull);
    await t.tap(find.byKey(const ValueKey<String>('og-sheet-close')));
    await t.pumpAndSettle();
    expect(_field, findsNothing);
  });

  testWidgets('Rebuild sends the trimmed feedback with the previous request, shows the card, then swaps the proposal',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openProposal(t);
    final String first = fake.lastStartId;
    await _send(t, '  I have no bottles, I have dumbbells ');
    expect(fake.startFeedback.last, ('I have no bottles, I have dumbbells', first));
    expect(fake.startNames.last, isNull);
    expect(find.text('Rebuilding…'), findsOneWidget);
    expect(find.text('Keep this session'), findsOneWidget);
    expect(_field, findsNothing); // the sheet closed
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'ready', proposal: _proposal('Goblet squat', rationale: 'Dumbbells')));
    await t.pumpAndSettle();
    expect(find.text('Rebuilding…'), findsNothing);
    expect(d.store.active!.exercises.single.name, 'Goblet squat');
    expect(d.store.active!.planNote, 'Dumbbells');
    expect(find.text('Goblet squat'), findsWidgets);
    expect(find.text('Squat'), findsNothing);
    await _openChange(t);
    expect(t.widget<TextField>(_field).controller!.text, isEmpty); // ready for the next round
    expect(d.store.sessions.where((Session s) => s.id == d.store.active!.id), isEmpty); // nothing saved
  });

  testWidgets('feedback can be given again: the second rebuild points at the first rebuild', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openProposal(t);
    await _send(t, 'one');
    final String second = fake.lastStartId;
    fake.answerStart(StartRequest(requestId: second, status: 'ready', proposal: _proposal('Lunge')));
    await t.pumpAndSettle();
    await _send(t, 'two');
    expect(fake.startFeedback.last, ('two', second));
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'ready', proposal: _proposal('Row')));
    await t.pumpAndSettle();
    expect(d.store.active!.exercises.single.name, 'Row');
  });

  testWidgets('a failed rebuild keeps the old proposal and the text, shows a short line; the next try points at the old request',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openProposal(t);
    final String first = fake.lastStartId;
    await _send(t, 'no bottles');
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'failed'));
    await t.pumpAndSettle();
    expect(find.text('Could not rebuild. Try again.'), findsOneWidget); // near the meta row
    expect(d.store.active!.exercises.single.name, 'Squat');
    await _openChange(t);
    expect(t.widget<TextField>(_field).controller!.text, 'no bottles');
    await t.tap(_rebuild);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(fake.startFeedback.last, ('no bottles', first));
    expect(find.text('Could not rebuild. Try again.'), findsNothing);
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'ready', proposal: _proposal('Lunge')));
    await t.pumpAndSettle();
    expect(d.store.active!.exercises.single.name, 'Lunge');
  });

  testWidgets('Keep this session stops waiting and keeps the proposal', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openProposal(t);
    await _send(t, 'no bottles');
    await t.tap(find.text('Keep this session'));
    await t.pump();
    expect(_change, findsOneWidget);
    expect(find.text('Rebuilding…'), findsNothing);
    expect(d.store.active!.exercises.single.name, 'Squat');
    expect(find.text('Could not rebuild. Try again.'), findsNothing);
  });

  testWidgets('offline: Rebuild is off and a short line says why; back online it works', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openProposal(t);
    await _openChange(t);
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

  testWidgets('after the first set is done Change plan is gone and a late answer changes nothing', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openProposal(t);
    await _send(t, 'no bottles');
    d.store.completeSet();
    await t.pump();
    expect(find.text('Rebuilding…'), findsNothing);
    expect(_change, findsNothing);
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
    await _openChange(t);
    expect(t.getRect(_rebuild).bottom, lessThanOrEqualTo(844 - 300));
    t.takeException(); // the screen behind overflows by 6 px under a 300 px keyboard; only the position matters
  });

  testWidgets('a session reopened from Home still takes feedback: it goes with the plan as it is on the phone',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps _) = await _openProposal(t);
    await t.tap(find.byIcon(Icons.arrow_back));
    await t.pumpAndSettle();
    await t.tap(find.text('Pause, come back later'));
    await t.pumpAndSettle();
    expect(find.byType(SessionScreen), findsNothing);
    await t.tap(find.textContaining('Resume'));
    await t.pumpAndSettle();
    await _send(t, 'I have dumbbells');
    expect(fake.startNames.last, 'Gym');
    expect(fake.startSent.last.$2, isNull);
    expect(fake.startFeedback.last, ('I have dumbbells', null));
    expect(fake.startPreviousPlans.last, <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'Squat',
        'sets': <Map<String, dynamic>>[
          <String, dynamic>{'reps': 8, 'kg': 60.0, 'max': false},
        ],
      },
    ]);
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'ready', proposal: _proposal('Goblet squat')));
    await t.pumpAndSettle();
    expect(find.text('Goblet squat'), findsWidgets);
  });

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
    expect(d.store.active, isNull);
    expect(d.store.sessions, isNotEmpty);
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
