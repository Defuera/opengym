import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/store.dart';
import 'package:opengym/theme.dart';

import 'support/set_taps.dart';

Future<AppStore> _open(WidgetTester t, List<Exercise> plan) async {
  t.view.physicalSize = const Size(390 * 2, 844 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final AppStore store = AppStore(InMemorySessionRepository());
  await store.load();
  store.begin(prepared: plan);
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(scaffoldBackgroundColor: OG.ground),
    home: SessionScreen(store: store),
  ));
  await t.pump();
  return store;
}

Exercise _raise() => Exercise(
      id: 'l',
      name: 'Lateral Raise',
      fresh: false,
      sets: <SetEntry>[for (int i = 0; i < 3; i++) SetEntry(reps: 12, kg: 6)],
    );

Exercise _time() => Exercise(
      id: 'w',
      name: 'Warm-Up',
      measure: measureTime,
      fresh: false,
      sets: <SetEntry>[SetEntry.time(2)],
    );

void main() {
  testWidgets('the check completes the current set; no bottom button while sets are open', (WidgetTester t) async {
    final AppStore store = await _open(t, <Exercise>[_raise(), _time()]);
    expect(find.text('Next exercise'), findsNothing);
    expect(find.text('Finish session'), findsNothing);
    expect(find.text('Complete set'), findsNothing);
    await tapCurrentCheck(t, store);
    final List<SetEntry> sets = store.currentExercise!.sets;
    expect(sets[0].done, isTrue);
    expect(sets[0].at, isNotNull);
    expect(store.curSet, 1);
  });

  testWidgets('tapping a done check undoes it: state, current set, no confirmation', (WidgetTester t) async {
    final AppStore store = await _open(t, <Exercise>[_raise()]);
    await tapCurrentCheck(t, store);
    await tapCurrentCheck(t, store);
    expect(store.currentExercise!.sets.map((SetEntry s) => s.done), <bool>[true, true, false]);
    await t.tap(setCheck(0, 0));
    await t.pump();
    final SetEntry s = store.currentExercise!.sets[0];
    expect(s.done, isFalse);
    expect(s.at, isNull);
    expect(store.curSet, 0);
    // committed: the open session in the store holds the undone set
    expect(store.active!.exercises.first.sets[0].done, isFalse);
    expect(store.hasDoneSet, isTrue);
  });

  testWidgets('any open set can be completed, also out of order', (WidgetTester t) async {
    final AppStore store = await _open(t, <Exercise>[_raise()]);
    await t.tap(setCheck(0, 2));
    await t.pump();
    final List<SetEntry> sets = store.currentExercise!.sets;
    expect(sets.map((SetEntry s) => s.done), <bool>[false, false, true]);
    expect(store.curSet, 0);
  });

  testWidgets('a time entry has a check too', (WidgetTester t) async {
    final AppStore store = await _open(t, <Exercise>[_time()]);
    await t.tap(setCheck(0, 0));
    await t.pump();
    expect(store.currentExercise!.sets.single.done, isTrue);
    expect(find.text('Finish session'), findsOneWidget);
    await t.tap(setCheck(0, 0));
    await t.pump();
    expect(store.currentExercise!.sets.single.done, isFalse);
    expect(find.text('Finish session'), findsNothing);
  });

  testWidgets('Next exercise and Finish session show when all sets are done; undo hides them', (WidgetTester t) async {
    final AppStore store = await _open(t, <Exercise>[_raise(), _time()]);
    for (int i = 0; i < 3; i++) {
      await tapCurrentCheck(t, store);
    }
    expect(find.text('Next exercise'), findsOneWidget);
    expect(find.text('Finish session'), findsNothing);
    await t.tap(setCheck(0, 1));
    await t.pump();
    expect(find.text('Next exercise'), findsNothing);
    await tapCurrentCheck(t, store);
    await t.tap(find.text('Next exercise'));
    await t.pump();
    expect(store.curEx, 1);
    expect(find.text('Next exercise'), findsNothing);
    await tapCurrentCheck(t, store);
    expect(find.text('Finish session'), findsOneWidget);
  });

  testWidgets('the check tap target is at least 44 x 44', (WidgetTester t) async {
    await _open(t, <Exercise>[_raise()]);
    final Size s = t.getSize(setCheck(0, 0));
    expect(s.width, greaterThanOrEqualTo(44));
    expect(s.height, greaterThanOrEqualTo(44));
  });
}
