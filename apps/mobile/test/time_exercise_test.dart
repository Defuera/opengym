import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/planner.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/store.dart';
import 'package:opengym/stores/plan_store.dart';
import 'package:opengym/theme.dart';
import 'package:opengym/widgets/exercise_picker.dart';
import 'package:opengym/widgets/set_editor_card.dart';

import 'support/set_taps.dart';
import 'support/fake_convex_client.dart';

Map<String, dynamic> _trip(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

Session _session(String id, int end, List<Exercise> ex) =>
    Session(id: id, kind: 'gym', type: 'Gym', startedAt: end - 1000, endedAt: end, exercises: ex);

Exercise _bike({double min = 25, double? km = 10.9}) => Exercise(
      id: 'b',
      name: 'Stationary bike',
      measure: measureTime,
      sets: <SetEntry>[SetEntry.time(min, distanceKm: km, done: true, at: 5)],
    );

Exercise _curl() => Exercise(
      id: 'c',
      name: 'Biceps Curl',
      sets: <SetEntry>[SetEntry(reps: 8, kg: 10, done: true)],
    );

void main() {
  group('model JSON', () {
    test('a time exercise round-trips in both shapes', () {
      final Session s = _session('s', 9000, <Exercise>[_bike(), _curl()]);
      final Session local = Session.fromJson(_trip(s.toJson()));
      final Exercise b = local.exercises.first;
      expect(b.isTime, isTrue);
      expect(b.sets.first.minutes, 25);
      expect(b.sets.first.distanceKm, 10.9);
      expect(b.sets.first.done, isTrue);
      expect(local.exercises.last.isTime, isFalse);

      final Map<String, dynamic> api = s.toContractJson();
      final List<Object?> ex = api['exercises'] as List<Object?>;
      final Map<String, dynamic> bike = ex.first as Map<String, dynamic>;
      expect(bike['measure'], 'time');
      expect(bike['sets'], <Object?>[
        <String, dynamic>{'minutes': 25.0, 'distanceKm': 10.9, 'at': 5},
      ]);
      expect((ex.last as Map<String, dynamic>).containsKey('measure'), isFalse);
      final Session fromServer = Session.fromJson(_trip(api));
      expect(fromServer.exercises.first.sets.first.minutes, 25);
      expect(fromServer.exercises.first.isTime, isTrue);
    });

    test('old JSON without measure loads as sets', () {
      final Exercise e = Exercise.fromJson(<String, dynamic>{
        'id': 'x',
        'name': 'Squat',
        'sets': <Object?>[
          <String, dynamic>{'reps': 5, 'kg': 100, 'max': false, 'done': true},
        ],
      });
      expect(e.measure, measureSets);
      expect(e.isTime, isFalse);
      expect(e.sets.first.reps, 5);
      expect(e.sets.first.minutes, isNull);
      expect(e.toContractJson().containsKey('measure'), isFalse);
    });

    test('plan exercises carry measure and minutes', () {
      final PlanExercise p = PlanExercise.fromJson(<String, dynamic>{
        'name': 'Bike',
        'measure': 'time',
        'sets': <Object?>[
          <String, dynamic>{'minutes': 20, 'distanceKm': 8},
        ],
      });
      expect(p.measure, 'time');
      expect(p.sets.first.minutes, 20);
      expect(PlanExercise.fromJson(_trip(p.toJson())).sets.first.distanceKm, 8);
      final Exercise e = PlanStore(client: FakeConvexClient())
          .exercisesFor(Plan(id: 'p', focus: '', createdAt: 1, source: 'rules', rationale: '', exercises: <PlanExercise>[p]))
          .first;
      expect(e.isTime, isTrue);
      expect(e.sets.first.minutes, 20);
      expect(e.sets.first.done, isFalse);
    });
  });

  group('planner', () {
    final List<Session> log = <Session>[
      _session('a', 1000, <Exercise>[_curl()]),
      _session('b', 3000, <Exercise>[_bike()]),
      _session('c', 2000, <Exercise>[
        Exercise(id: 'z', name: 'biceps curl', sets: <SetEntry>[SetEntry(reps: 5, kg: 5, done: true)]),
        Exercise(id: 'y', name: 'Leg Press', sets: <SetEntry>[SetEntry(reps: 5, kg: 50, done: true)]),
      ]),
    ];

    test('loggedExercises: most recent first, latest spelling, measure', () {
      final List<LoggedExercise> l = loggedExercises(log);
      expect(l.map((LoggedExercise x) => x.name).toList(), <String>['Stationary bike', 'Leg Press', 'biceps curl']);
      expect(l.first.measure, measureTime);
      expect(loggedExercises(<Session>[]), isEmpty);
    });

    test('makeExercise keeps the measure of the log, a new name uses the asked one', () {
      final Exercise b = makeExercise(log, 'Stationary bike');
      expect(b.isTime, isTrue);
      expect(b.sets.first.minutes, 25);
      expect(b.sets.first.done, isFalse);
      expect(b.fresh, isFalse);
      final Exercise n = makeExercise(log, 'Plank', measure: measureTime);
      expect(n.isTime, isTrue);
      expect(n.sets.single.minutes, defaultMinutes);
      expect(makeExercise(log, 'Rows').isTime, isFalse);
    });

    test('stats ignore time entries', () {
      final StatsResult st = stats(<Session>[_session('a', 5000, <Exercise>[_bike(), _curl()])], 7, nowMs: 6000);
      expect(st.sets, 1);
      expect(st.best, 'Biceps Curl');
    });

    test('timeText', () {
      expect(timeText(25), '25 min');
      expect(timeText(25, 10.9), '25 min, 10.9 km');
    });
  });

  group('exercise picker', () {
    const List<ExerciseOption> opts = <ExerciseOption>[
      ExerciseOption('Stationary bike', timed: true),
      ExerciseOption('Biceps Curl'),
      ExerciseOption('Leg Press'),
    ];
    ExerciseChoice? result;
    bool closed = false;

    Future<void> open(WidgetTester t, List<ExerciseOption> options) async {
      result = null;
      closed = false;
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: OG.ground),
        home: Builder(
          builder: (BuildContext c) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showExercisePicker(c, title: 'Add exercise', options: options);
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('lists the exercises of the log, in the given order', (WidgetTester t) async {
      await open(t, opts);
      expect(find.text('Stationary bike'), findsOneWidget);
      expect(find.text('Biceps Curl'), findsOneWidget);
      expect(find.text('Leg Press'), findsOneWidget);
      expect(find.text('Bench press'), findsNothing); // no built-in list
      expect(t.getTopLeft(find.text('Stationary bike')).dy, lessThan(t.getTopLeft(find.text('Leg Press')).dy));
    });

    testWidgets('an empty log shows the field and a short line', (WidgetTester t) async {
      await open(t, const <ExerciseOption>[]);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.textContaining('No exercises in your log yet'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('typing filters: every word must be part of the name', (WidgetTester t) async {
      await open(t, opts);
      await t.enterText(find.byType(TextField), 'bic');
      await t.pump();
      expect(find.text('Biceps Curl'), findsOneWidget);
      expect(find.text('Leg Press'), findsNothing);
      expect(find.text('Stationary bike'), findsNothing);
      await t.enterText(find.byType(TextField), 'PRESS leg');
      await t.pump();
      expect(find.text('Leg Press'), findsOneWidget);
      expect(find.text('Biceps Curl'), findsNothing);
      await t.enterText(find.byType(TextField), 'bike');
      await t.pump();
      expect(find.text('Stationary bike'), findsOneWidget);
    });

    testWidgets('a name that matches nothing offers Add and asks the measure', (WidgetTester t) async {
      await open(t, opts);
      await t.enterText(find.byType(TextField), 'cycling');
      await t.pump();
      expect(find.text('Biceps Curl'), findsNothing);
      expect(find.text('Add "Cycling"'), findsOneWidget);
      await t.tap(find.text('Add "Cycling"'));
      await t.pumpAndSettle();
      expect(find.text('Sets and reps'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      await t.tap(find.text('Time'));
      await t.pumpAndSettle();
      expect(closed, isTrue);
      expect(result!.name, 'Cycling');
      expect(result!.timed, isTrue);
    });

    testWidgets('Done does the same as Add; sets and reps is the other answer', (WidgetTester t) async {
      await open(t, opts);
      await t.enterText(find.byType(TextField), 'chin up');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(find.text('Sets and reps'), findsOneWidget);
      await t.tap(find.text('Sets and reps'));
      await t.pumpAndSettle();
      expect(result!.name, 'Chin up');
      expect(result!.timed, isFalse);
    });

    testWidgets('an exact match reuses the log spelling and measure, no question', (WidgetTester t) async {
      await open(t, opts);
      await t.enterText(find.byType(TextField), '  stationary   BIKE ');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(closed, isTrue);
      expect(result!.name, 'Stationary bike');
      expect(result!.timed, isTrue);
    });

    testWidgets('tapping a row returns it with its measure', (WidgetTester t) async {
      await open(t, opts);
      await t.tap(find.text('Biceps Curl'));
      await t.pumpAndSettle();
      expect(result!.name, 'Biceps Curl');
      expect(result!.timed, isFalse);
    });
  });

  group('session screen', () {
    Future<AppStore> start(WidgetTester t, List<Exercise> prepared) async {
      final AppStore store = AppStore(InMemorySessionRepository());
      await store.load();
      store.begin(prepared: prepared);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: OG.ground),
        home: SessionScreen(store: store),
      ));
      await t.pump();
      return store;
    }

    testWidgets('a time exercise shows minutes, distance and Complete; no reps or kg', (WidgetTester t) async {
      final AppStore store = await start(t, <Exercise>[
        Exercise(id: 'b', name: 'Stationary bike', measure: measureTime, fresh: false, sets: <SetEntry>[SetEntry.time(20)]),
      ]);
      expect(find.text('MIN'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('time-distance')), findsNothing);
      await t.tap(find.byKey(const ValueKey<String>('time-add-distance')));
      await t.pump();
      expect(find.byKey(const ValueKey<String>('time-distance')), findsOneWidget);
      expect(setCheck(0, 0), findsOneWidget);
      expect(find.text('REPS'), findsNothing);
      expect(find.text('KG'), findsNothing);
      expect(find.text('Last rep failed'), findsNothing);
      expect(find.textContaining('First time here'), findsNothing);
      expect(find.text('0 / 1'), findsOneWidget);

      await t.tap(find.byType(StepperButton).last);
      await t.pump();
      expect(store.currentSet!.minutes, 21);
      await t.longPress(find.byType(StepperButton).last);
      await t.pump();
      expect(store.currentSet!.minutes, 26);
      await t.tap(find.byType(StepperButton).first);
      await t.pump();
      expect(store.currentSet!.minutes, 25);

      await t.enterText(find.byKey(const ValueKey<String>('time-distance')), '10.9');
      await t.pump();
      expect(store.currentSet!.distanceKm, 10.9);

      await tapCurrentCheck(t, store);
      await t.pump();
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.text('Finish session'), findsOneWidget);

      store.finish();
      final Exercise saved = store.sessions.single.exercises.single;
      expect(saved.isTime, isTrue);
      expect(saved.sets.single.minutes, 25);
      expect(saved.sets.single.distanceKm, 10.9);
      final List<Object?> api = store.sessions.single.toContractJson()['exercises'] as List<Object?>;
      expect((api.single as Map<String, dynamic>)['measure'], 'time');
    });

    testWidgets('an exercise with sets still shows reps and kg', (WidgetTester t) async {
      await start(t, <Exercise>[
        Exercise(id: 'c', name: 'Biceps Curl', sets: <SetEntry>[SetEntry(reps: 8, kg: 10)]),
      ]);
      expect(find.text('REPS'), findsOneWidget);
      expect(setCheck(0, 0), findsOneWidget);
    });

    testWidgets('Add exercise lists the log, filters, and adds a new time exercise', (WidgetTester t) async {
      final AppStore store = AppStore(InMemorySessionRepository());
      await store.load();
      store.sessions.add(_session('old', 1000, <Exercise>[_curl()]));
      store.begin(prepared: <Exercise>[]);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: OG.ground),
        home: SessionScreen(store: store),
      ));
      await t.pump();
      await t.tap(find.text('Add'));
      await t.pumpAndSettle();
      expect(find.text('Biceps Curl'), findsOneWidget);
      expect(find.text('Bench press'), findsNothing);
      await t.enterText(find.byType(TextField), 'treadmill');
      await t.pump();
      await t.tap(find.text('Add "Treadmill"'));
      await t.pumpAndSettle();
      await t.tap(find.text('Time'));
      await t.pumpAndSettle();
      expect(store.currentExercise!.name, 'Treadmill');
      expect(store.currentExercise!.isTime, isTrue);
      expect(setCheck(0, 0), findsOneWidget);
    });
  });

  test('time entry keeps minutes in range', () async {
    final AppStore store = AppStore(InMemorySessionRepository());
    await store.load();
    store.begin(prepared: <Exercise>[
      Exercise(id: 'b', name: 'Bike', measure: measureTime, sets: <SetEntry>[SetEntry.time(1)]),
    ]);
    store.changeMinutes(-1);
    expect(store.currentSet!.minutes, 0.9167);
    for (int i = 0; i < 30; i++) {
      store.changeMinutes(-1);
    }
    expect(store.currentSet!.minutes, 0.0833);
    store.currentSet!.minutes = 598;
    store.changeMinutes(5);
    expect(store.currentSet!.minutes, 600);
    store.setDistance(0);
    expect(store.currentSet!.distanceKm, isNull);
    store.addSet();
    expect(store.currentExercise!.sets.length, 2);
    expect(store.currentSet!.minutes, 600);
  });
}
