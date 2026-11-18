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

Session _home(String focus, int endedAt, List<Exercise> exercises) {
  return Session(
    id: 'home$focus$endedAt',
    kind: 'gym',
    type: 'Home',
    focus: focus,
    startedAt: endedAt - 1800000,
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

  test('focus rotation is empty with no history (no starter foci)', () {
    expect(focusRotation(<Session>[]), isEmpty);
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

  test('planFor repeats the last session of the same activity and focus, else empty', () {
    final List<Session> sessions = <Session>[
      _gym('Push', 1000, <Exercise>[_ex('Dips', <double>[0])]),
      _home('Quick', 2000, <Exercise>[_ex('Press-up', <double>[0])]),
    ];
    final List<Exercise> plan = planFor(sessions, 'Gym', 'Push');
    expect(plan.map((Exercise e) => e.name).toList(), <String>['Dips']);
    expect(plan.first.fresh, isFalse);
    expect(planFor(sessions, ' home ', 'quick').map((Exercise e) => e.name), <String>['Press-up']);
    expect(planFor(sessions, 'Home', 'Push'), isEmpty);
    expect(planFor(<Session>[], 'Gym', 'Pull'), isEmpty);
    expect(planFor(<Session>[], 'Gym', null), isEmpty);
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

  test('activityKey lower-cases, trims and collapses spaces', () {
    expect(activityKey('  Hotel   GYM '), 'hotel gym');
    expect(activityKey('Run'), activityKey('run '));
    expect(activityNameFromText('hotel gym, 30 min'), 'Hotel gym');
    expect(activityNameFromText('  '), 'Gym');
    expect(activityNameFromText('x' * 60).length, 40);
  });
}
