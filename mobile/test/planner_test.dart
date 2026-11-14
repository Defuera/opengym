import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/models.dart';
import 'package:opengym/planner.dart';

Exercise _ex(String name, List<double> kgs) {
  return Exercise(
    id: name,
    name: name,
    sets: kgs
        .map((double k) => SetEntry(reps: 5, kg: k, done: true))
        .toList(),
  );
}

Session _gym(String type, int endedAt, List<Exercise> exercises) {
  return Session(
    id: '$type$endedAt',
    kind: 'gym',
    type: type,
    startedAt: endedAt - 3600000,
    endedAt: endedAt,
    exercises: exercises,
  );
}

void main() {
  test('bench press defaults are 6x20, 6x40, 6x60, then 1x60 max', () {
    final List<SetEntry> sets = defaultSets('Bench press');
    expect(sets.map((SetEntry s) => s.reps).toList(), <int>[6, 6, 6, 1]);
    expect(sets.map((SetEntry s) => s.kg).toList(), <double>[20, 40, 60, 60]);
    expect(sets.map((SetEntry s) => s.isMax).toList(),
        <bool>[false, false, false, true]);
    expect(sets.every((SetEntry s) => !s.done), isTrue);
  });

  test('other exercises default to 3 sets of 8 at 0 kg', () {
    final List<SetEntry> sets = defaultSets('Squat');
    expect(sets.length, 3);
    expect(sets.every((SetEntry s) => s.reps == 8 && s.kg == 0), isTrue);
  });

  test('predictions follow starter order with no history', () {
    final List<Prediction> p = predictions(<Session>[]);
    expect(p.map((Prediction x) => x.type).toList(), <String>['Push', 'Pull', 'Legs']);
  });

  test('predictions rotate after a logged Push session', () {
    final List<Session> sessions = <Session>[
      _gym('Push', 1000, <Exercise>[_ex('Bench press', <double>[60])]),
    ];
    final List<Prediction> p = predictions(sessions);
    expect(p.map((Prediction x) => x.type).toList(), <String>['Pull', 'Legs', 'Push']);
  });

  test('lastSetsFor prefills from the latest session, not done', () {
    final List<Session> sessions = <Session>[
      _gym('Push', 1000, <Exercise>[_ex('Bench press', <double>[50])]),
      _gym('Push', 2000, <Exercise>[_ex('Bench press', <double>[55, 65])]),
    ];
    final List<SetEntry>? sets = lastSetsFor(sessions, 'Bench press');
    expect(sets, isNotNull);
    expect(sets!.map((SetEntry s) => s.kg).toList(), <double>[55, 65]);
    expect(sets.every((SetEntry s) => !s.done), isTrue);
    expect(lastSetsFor(sessions, 'Squat'), isNull);
  });

  test('planFor reuses the last session of that type', () {
    final List<Session> sessions = <Session>[
      _gym('Push', 1000, <Exercise>[_ex('Dips', <double>[0])]),
    ];
    final List<Exercise> plan = planFor(sessions, 'Push');
    expect(plan.map((Exercise e) => e.name).toList(), <String>['Dips']);
    expect(plan.first.fresh, isFalse);
    expect(planFor(<Session>[], 'Pull').length, 4);
    expect(planFor(<Session>[], 'Custom'), isEmpty);
  });

  test('stats counts sessions, delta, active days, sets and top exercise', () {
    const int now = 1700000000000;
    final List<Session> sessions = <Session>[
      _gym('Push', now - 10 * dayMs, <Exercise>[_ex('Bench press', <double>[40])]),
      _gym('Push', now - 3 * dayMs, <Exercise>[_ex('Bench press', <double>[50])]),
      _gym('Pull', now - dayMs, <Exercise>[
        _ex('Bench press', <double>[40, 60]),
        _ex('Squat', <double>[80]),
      ]),
    ];
    final StatsResult r = stats(sessions, 7, nowMs: now);
    expect(r.sessions, 2);
    expect(r.delta, 1);
    expect(r.days, 2);
    expect(r.sets, 4);
    expect(r.best, 'Bench press');
    expect(r.top, 60);
  });
}
