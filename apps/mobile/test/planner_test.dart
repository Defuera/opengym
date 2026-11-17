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

Session _gym(String focus, int endedAt, List<Exercise> exercises) {
  return Session(
    id: '$focus$endedAt',
    kind: 'gym',
    type: 'Gym',
    focus: focus,
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

  test('focus rotation follows starter order with no history', () {
    final List<FocusRank> p = focusRotation(<Session>[]);
    expect(p.map((FocusRank x) => x.focus).toList(), <String>['Push', 'Pull', 'Legs']);
  });

  test('focus rotation uses only the foci in the log, least recent first', () {
    final List<Session> sessions = <Session>[
      _gym('Upper', 1000, <Exercise>[_ex('Bench press', <double>[60])]),
      _gym('Legs', 2000, <Exercise>[_ex('Squat', <double>[80])]),
      _gym('Full body', 3000, <Exercise>[_ex('Squat', <double>[80])]),
      _gym('Upper', 4000, <Exercise>[_ex('Bench press', <double>[60])]),
    ];
    final List<FocusRank> p = focusRotation(sessions);
    expect(p.map((FocusRank x) => x.focus).toList(), <String>['Legs', 'Full body', 'Upper']);
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

  test('planFor reuses the last gym session with that focus', () {
    final List<Session> sessions = <Session>[
      _gym('Push', 1000, <Exercise>[_ex('Dips', <double>[0])]),
    ];
    final List<Exercise> plan = planFor(sessions, 'Push');
    expect(plan.map((Exercise e) => e.name).toList(), <String>['Dips']);
    expect(plan.first.fresh, isFalse);
    expect(planFor(<Session>[], 'Pull').length, 4);
    expect(planFor(<Session>[], 'Custom'), isEmpty);
    expect(planFor(<Session>[], null), isEmpty);
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

  test('rankActivities ranks activities: Gym once with the focus that is due', () {
    const int now = 1700000000000;
    final List<Session> sessions = <Session>[
      _gym('Upper', now - 6 * dayMs, <Exercise>[_ex('Row', <double>[40])]),
      _gym('Legs', now - 2 * dayMs, <Exercise>[_ex('Squat', <double>[80])]),
      Session(id: 'r1', kind: 'activity', type: 'Run', focus: 'Long', startedAt: now - 9 * dayMs, endedAt: now - 9 * dayMs),
      Session(id: 'r2', kind: 'activity', type: 'Run', focus: 'Easy', startedAt: now - 3 * dayMs, endedAt: now - 3 * dayMs),
    ];
    final List<Prediction> p = rankActivities(sessions, nowMs: now);
    expect(p.where((Prediction x) => x.type == 'Gym').length, 1);
    expect(p.first.focus, 'Upper');
    expect(p.first.reason, 'Last legs session was 2 days ago');
    expect(p[1].type, 'Run');
    expect(p[1].focus, 'Long');
    expect(rankActivities(<Session>[], nowMs: now).single.focus, 'Push');
  });

  test('gymFoci puts the advised focus first', () {
    final List<Session> sessions = <Session>[
      _gym('Upper', 1000, <Exercise>[_ex('Row', <double>[40])]),
    ];
    expect(gymFoci(sessions, advised: 'Legs').first, 'Legs');
    // The log has a focus, so only logged foci (plus the advised one) show.
    expect(gymFoci(sessions).toList(), <String>['Upper']);
    expect(gymFoci(sessions, advised: 'Upper').toList(), <String>['Upper']);
    expect(gymFoci(<Session>[]).toList(), <String>['Push', 'Pull', 'Legs']);
  });
}
