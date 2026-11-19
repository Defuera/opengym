import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_edit_screen.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/store.dart';
import 'package:opengym/stores/countdown_store.dart';
import 'package:opengym/theme.dart';

import 'support/fake_convex_client.dart';
import 'support/fake_countdown_signal.dart';
import 'support/set_taps.dart';
import 'support/test_deps.dart';

/// A clock the test moves by hand.
class _Clock {
  DateTime t = DateTime(2026, 11, 19, 10);
  DateTime call() => t;
  void add(Duration d) => t = t.add(d);
}

ValueKey<String> _k(String s) => ValueKey<String>(s);

Exercise _bike({List<SetEntry>? sets}) => Exercise(
      id: 'b',
      name: 'Stationary bike',
      measure: measureTime,
      fresh: false,
      sets: sets ?? <SetEntry>[SetEntry.time(10)],
    );

void main() {
  group('CountdownStore', () {
    late _Clock clock;
    late CountdownStore cd;
    late int alerts;
    late int done;

    setUp(() {
      clock = _Clock();
      alerts = 0;
      done = 0;
      cd = CountdownStore(now: clock.call, alert: () => alerts++);
    });
    tearDown(() => cd.dispose());

    test('starts from the minutes: 0.5 min is 30 s', () {
      final Object e = Object();
      cd.start(e, 0.5, () => done++);
      expect(cd.active, isTrue);
      expect(cd.isFor(e), isTrue);
      expect(cd.remaining, const Duration(seconds: 30));
    });

    test('at zero it ends, alerts and calls done once', () {
      cd.start(Object(), 1, () => done++);
      clock.add(const Duration(seconds: 59));
      cd.tick();
      expect(done, 0);
      expect(cd.remaining, const Duration(seconds: 1));
      clock.add(const Duration(seconds: 1));
      cd.tick();
      cd.tick();
      expect(done, 1);
      expect(alerts, 1);
      expect(cd.active, isFalse);
    });

    test('done runs after the countdown ended', () {
      bool activeInDone = true;
      cd.start(Object(), 1, () => activeInDone = cd.active);
      clock.add(const Duration(minutes: 1));
      cd.tick();
      expect(activeInDone, isFalse);
    });

    test('pause keeps the remaining time, resume continues from it', () {
      cd.start(Object(), 1, () => done++);
      clock.add(const Duration(seconds: 20));
      cd.pause();
      expect(cd.paused, isTrue);
      clock.add(const Duration(minutes: 5));
      cd.tick();
      expect(done, 0);
      expect(cd.remaining, const Duration(seconds: 40));
      cd.resume();
      expect(cd.paused, isFalse);
      clock.add(const Duration(seconds: 10));
      expect(cd.remaining, const Duration(seconds: 30));
      clock.add(const Duration(seconds: 30));
      cd.tick();
      expect(done, 1);
    });

    test('reset stops it without done or alert', () {
      cd.start(Object(), 1, () => done++);
      cd.cancel();
      expect(cd.active, isFalse);
      clock.add(const Duration(minutes: 2));
      cd.tick();
      expect(done, 0);
      expect(alerts, 0);
    });

    test('a second start replaces the first', () {
      final Object a = Object();
      final Object b = Object();
      int doneA = 0;
      cd.start(a, 1, () => doneA++);
      cd.start(b, 2, () => done++);
      expect(cd.isFor(a), isFalse);
      expect(cd.isFor(b), isTrue);
      expect(cd.remaining, const Duration(minutes: 2));
      clock.add(const Duration(minutes: 2));
      cd.tick();
      expect(doneA, 0);
      expect(done, 1);
    });

    test('completes when the end time passed while no tick ran', () {
      cd.start(Object(), 10, () => done++);
      clock.add(const Duration(hours: 2));
      expect(cd.remaining, Duration.zero);
      cd.tick();
      expect(done, 1);
      expect(cd.active, isFalse);
    });
  });

  group('the sound at the end time', () {
    late _Clock clock;
    late FakeCountdownSignal sig;
    late AppStore store;
    late SetEntry first;

    setUp(() async {
      clock = _Clock();
      sig = FakeCountdownSignal();
      store = AppStore(
        InMemorySessionRepository(),
        countdown: CountdownStore(now: clock.call, alert: () {}, signal: sig),
      );
      await store.load();
      first = SetEntry.time(2);
      store.begin(prepared: <Exercise>[
        _bike(sets: <SetEntry>[first, SetEntry.time(3)]),
      ]);
    });
    tearDown(() => store.countdown.cancel());

    test('Start plans it at the end time with the exercise name', () {
      store.startCountdown(0);
      expect(sig.at, clock.t.add(const Duration(minutes: 2)));
      expect(sig.title, 'Stationary bike');
    });

    test('Pause cancels it, Resume plans it at the new end time', () {
      store.startCountdown(0);
      clock.add(const Duration(seconds: 30));
      store.countdown.pause();
      expect(sig.at, isNull);
      clock.add(const Duration(minutes: 10));
      store.countdown.resume();
      expect(sig.at, clock.t.add(const Duration(seconds: 90)));
      expect(sig.title, 'Stationary bike');
    });

    test('Reset cancels it', () {
      store.startCountdown(0);
      store.countdown.cancel();
      expect(sig.at, isNull);
    });

    test('entry removed, minutes changed, checked by hand', () {
      store.startCountdown(0);
      store.removeSetAt(0);
      expect(sig.at, isNull);
      first = store.currentExercise!.sets.first;
      store.startCountdown(0);
      store.changeMinutes(1);
      expect(sig.at, isNull);
      store.startCountdown(0);
      store.toggleSet(0);
      expect(sig.at, isNull);
    });

    test('session finished or discarded', () {
      store.startCountdown(0);
      store.toggleSet(1);
      store.finish();
      expect(sig.at, isNull);
      store.begin(prepared: <Exercise>[_bike()]);
      store.startCountdown(0);
      store.discard();
      expect(sig.at, isNull);
    });

    test('a second countdown replaces the first plan', () {
      store.startCountdown(0);
      clock.add(const Duration(seconds: 10));
      store.startCountdown(1);
      expect(sig.at, clock.t.add(const Duration(minutes: 3)));
      expect(sig.calls.where((String c) => c == 'schedule').length, 2);
    });

    test('at zero it is not cancelled: it has fired by itself', () {
      store.startCountdown(0);
      clock.add(const Duration(minutes: 2));
      store.countdown.tick();
      expect(sig.calls, <String>['schedule']);
      expect(first.done, isTrue);
    });

    test('permission denied: the countdown still works', () {
      final FakeCountdownSignal denied = FakeCountdownSignal(granted: false);
      final CountdownStore cd = CountdownStore(now: clock.call, alert: () {}, signal: denied);
      int done = 0;
      cd.start(Object(), 1, () => done++, title: 'Bike');
      clock.add(const Duration(minutes: 1));
      cd.tick();
      expect(denied.at, isNull);
      expect(done, 1);
    });

    test('a failing plugin never breaks the countdown', () async {
      final CountdownStore cd =
          CountdownStore(now: clock.call, alert: () {}, signal: FakeCountdownSignal(fail: true));
      int done = 0;
      cd.start(Object(), 1, () => done++, title: 'Bike');
      cd.pause();
      cd.resume();
      clock.add(const Duration(minutes: 1));
      cd.tick();
      await Future<void>.delayed(Duration.zero);
      expect(done, 1);
    });
  });

  group('AppStore and the countdown', () {
    late _Clock clock;
    late AppStore store;
    late SetEntry first;

    setUp(() async {
      clock = _Clock();
      store = AppStore(InMemorySessionRepository(), countdown: CountdownStore(now: clock.call, alert: () {}));
      await store.load();
      first = SetEntry.time(2);
      store.begin(prepared: <Exercise>[
        _bike(sets: <SetEntry>[first, SetEntry.time(3)]),
        Exercise(id: 'c', name: 'Curl', fresh: false, sets: <SetEntry>[SetEntry(reps: 8, kg: 10)]),
      ]);
    });
    tearDown(() => store.countdown.cancel());

    test('zero marks the entry done like the check mark and does not start the next', () {
      store.startCountdown(0);
      clock.add(const Duration(minutes: 2));
      store.countdown.tick();
      expect(first.done, isTrue);
      expect(first.at, isNotNull);
      expect(store.curSet, 1);
      expect(store.countdown.active, isFalse);
    });

    test('zero completes the entry although another exercise is shown', () {
      store.startCountdown(0);
      store.pickExercise(1);
      clock.add(const Duration(minutes: 2));
      store.countdown.tick();
      expect(first.done, isTrue);
      expect(store.curEx, 1);
      expect(store.countdown.active, isFalse);
    });

    test('it survives a switch to another exercise and back', () {
      store.startCountdown(0);
      store.pickExercise(1);
      store.changeReps(1);
      store.pickExercise(0);
      expect(store.countdown.isFor(first), isTrue);
    });

    test('removing the entry cancels it', () {
      store.startCountdown(0);
      store.removeSetAt(0);
      expect(store.countdown.active, isFalse);
    });

    test('removing another entry keeps it', () {
      store.startCountdown(0);
      store.removeSetAt(1);
      expect(store.countdown.active, isTrue);
    });

    test('changing the minutes cancels it', () {
      store.startCountdown(0);
      store.pickSet(0);
      store.changeMinutes(1);
      expect(store.countdown.active, isFalse);
    });

    test('marking it done by hand cancels it', () {
      store.startCountdown(0);
      store.toggleSet(0);
      expect(store.countdown.active, isFalse);
    });

    test('finish and discard cancel it', () {
      store.startCountdown(0);
      store.toggleSet(1);
      store.finish();
      expect(store.countdown.active, isFalse);
      store.begin(prepared: <Exercise>[_bike()]);
      store.startCountdown(0);
      store.discard();
      expect(store.countdown.active, isFalse);
    });

    test('a done entry cannot start', () {
      store.toggleSet(0);
      store.startCountdown(0);
      expect(store.countdown.active, isFalse);
    });
  });

  group('session screen', () {
    late _Clock clock;
    late AppStore store;

    Future<void> open(WidgetTester t, List<Exercise> prepared) async {
      clock = _Clock();
      store = AppStore(InMemorySessionRepository(), countdown: CountdownStore(now: clock.call, alert: () {}));
      await store.load();
      store.begin(prepared: prepared);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: OG.ground),
        home: SessionScreen(store: store),
      ));
      await t.pump();
    }

    Future<void> passTime(WidgetTester t, Duration d) async {
      clock.add(d);
      await t.pump(const Duration(milliseconds: 250));
    }

    String shown(WidgetTester t) => t.widget<Text>(find.byKey(_k('countdown-time'))).data!;

    testWidgets('Start shows the time and hides the steppers; zero marks it done', (WidgetTester t) async {
      await open(t, <Exercise>[_bike(sets: <SetEntry>[SetEntry.time(0.5)])]);
      expect(find.byKey(_k('countdown-start')), findsOneWidget);
      expect(find.text('SEC'), findsOneWidget);
      await t.tap(find.byKey(_k('countdown-start')));
      await t.pump();
      expect(shown(t), '0:30');
      expect(find.text('SEC'), findsNothing);
      expect(find.byKey(_k('countdown-start')), findsNothing);
      expect(find.text('Pause'), findsOneWidget);
      await passTime(t, const Duration(seconds: 10));
      expect(shown(t), '0:20');
      await passTime(t, const Duration(seconds: 20));
      expect(store.active!.exercises.first.sets.first.done, isTrue);
      expect(find.byKey(_k('countdown-time')), findsNothing);
      expect(store.countdown.active, isFalse);
      expect(find.byKey(_k('countdown-start')), findsNothing);
    });

    testWidgets('Pause holds the time, Resume goes on, Reset brings the card back', (WidgetTester t) async {
      await open(t, <Exercise>[_bike(sets: <SetEntry>[SetEntry.time(1)])]);
      await t.tap(find.byKey(_k('countdown-start')));
      await t.pump();
      await passTime(t, const Duration(seconds: 15));
      await t.tap(find.byKey(_k('countdown-toggle')));
      await t.pump();
      expect(find.text('Resume'), findsOneWidget);
      await passTime(t, const Duration(seconds: 30));
      expect(shown(t), '0:45');
      await t.tap(find.byKey(_k('countdown-toggle')));
      await t.pump();
      expect(find.text('Pause'), findsOneWidget);
      await passTime(t, const Duration(seconds: 5));
      expect(shown(t), '0:40');
      await t.tap(find.byKey(_k('countdown-reset')));
      await t.pump();
      expect(find.byKey(_k('countdown-time')), findsNothing);
      expect(find.text('MIN'), findsOneWidget);
      expect(find.byKey(_k('countdown-start')), findsOneWidget);
      expect(store.active!.exercises.first.sets.first.done, isFalse);
    });

    testWidgets('a done entry has no Start; another row shows the time in place of its minutes', (WidgetTester t) async {
      await open(t, <Exercise>[
        _bike(sets: <SetEntry>[SetEntry.time(5), SetEntry.time(7)]),
      ]);
      await t.tap(find.byKey(_k('countdown-start')));
      await t.pump();
      expect(find.text('7 min'), findsOneWidget);
      await t.tap(find.text('7 min'));
      await t.pump();
      // The countdown belongs to entry 0, now an unselected row.
      expect(find.byKey(_k('countdown-row-time')), findsOneWidget);
      expect(find.text('5 min'), findsNothing);
      expect(find.text('5:00'), findsOneWidget);
      expect(find.byKey(_k('countdown-time')), findsNothing);
      expect(find.byKey(_k('countdown-start')), findsOneWidget);
      store.countdown.cancel();
      await t.pump();
      await t.tap(setCheck(0, 1));
      await t.pump();
      await t.tap(setCheck(0, 0));
      await t.pump();
      expect(store.active!.exercises.first.sets.every((SetEntry x) => x.done), isTrue);
      expect(find.byKey(_k('countdown-start')), findsNothing);
    });

    testWidgets('the countdown stays when the screen is rebuilt', (WidgetTester t) async {
      await open(t, <Exercise>[_bike(sets: <SetEntry>[SetEntry.time(1)])]);
      await t.tap(find.byKey(_k('countdown-start')));
      await t.pump();
      await passTime(t, const Duration(seconds: 10));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: OG.ground),
        home: SessionScreen(store: store),
      ));
      await t.pump();
      expect(shown(t), '0:50');
      store.countdown.cancel();
      await t.pump();
    });

    testWidgets('no Start in the session edit screen', (WidgetTester t) async {
      final FakeConvexClient fake = FakeConvexClient();
      final AppDeps d = await testDeps(fake);
      final Session s = Session(
        id: 's',
        kind: 'gym',
        type: 'Gym',
        startedAt: 1000,
        endedAt: 2000,
        exercises: <Exercise>[
          Exercise(id: 'b', name: 'Bike', measure: measureTime, sets: <SetEntry>[SetEntry.time(10, done: true, at: 5)]),
        ],
      );
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: OG.ground),
        home: SessionEditScreen(deps: d, session: s),
      ));
      await t.pump();
      expect(find.text('MIN'), findsOneWidget);
      expect(find.byKey(_k('countdown-start')), findsNothing);
    });
  });
}
