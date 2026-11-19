import 'package:opengym/models.dart';

PlanExercise _ex(String name, int sets, int reps, double kg, {String? note}) => PlanExercise(
      name: name,
      note: note,
      sets: <PlanSet>[for (int i = 0; i < sets; i++) PlanSet(reps: reps, kg: kg)],
    );

PlanExercise _hold(String name, double minutes) => PlanExercise(
      name: name,
      measure: 'time',
      sets: <PlanSet>[PlanSet(reps: 0, kg: 0, minutes: minutes), PlanSet(reps: 0, kg: 0, minutes: minutes)],
    );

PlanExercise _bike(double minutes) => PlanExercise(
      name: 'Stationary bike',
      measure: 'time',
      sets: <PlanSet>[PlanSet(reps: 0, kg: 0, minutes: minutes)],
    );

/// One phase of the knee program: sessions A, B and Bike, written in full.
ProgramPhase _phase(String title, int from, int to, String note, {required int sets, required int reps, required double kg, required double bike}) {
  return ProgramPhase(
    title: title,
    weekFrom: from,
    weekTo: to,
    note: note,
    sessions: <ProgramSession>[
      ProgramSession(
        key: 'A',
        title: 'Session A',
        activity: 'Gym',
        exercises: <PlanExercise>[
          _ex('Leg press', sets, reps, kg),
          _ex('Hamstring curl', sets, reps, kg / 2),
          _hold('Wall sit', 0.5),
        ],
      ),
      ProgramSession(
        key: 'B',
        title: 'Session B',
        activity: 'Gym',
        exercises: <PlanExercise>[
          _ex('Step-up', sets, reps, 0),
          _ex('Calf raise', sets, reps + 4, kg / 2, note: 'Slow on the way down'),
        ],
        note: 'Stop if the knee hurts.',
      ),
      ProgramSession(key: 'Bike', title: 'Bike', activity: 'Cycling', exercises: <PlanExercise>[_bike(bike)]),
    ],
  );
}

/// The realistic proposal of a four week knee program for skiing.
Program kneeValue() => Program(
      title: 'Knee for skiing',
      purpose: 'Get the left knee ready for skiing on 19 Dec.',
      startsOn: '2026-11-16',
      endsOn: '2026-12-13',
      week: const <String>['A', 'B', 'A', 'Bike', 'Bike'],
      phases: <ProgramPhase>[
        _phase('Settle', 1, 1, 'Light and slow. Learn the moves.', sets: 2, reps: 12, kg: 30, bike: 20),
        _phase('Build', 2, 2, 'Add one set.', sets: 3, reps: 12, kg: 35, bike: 25),
        _phase('Load', 3, 3, 'Heavier, fewer reps.', sets: 3, reps: 10, kg: 45, bike: 30),
        _phase('Peak and test', 4, 4, 'Hold the load, then test.', sets: 3, reps: 8, kg: 55, bike: 30),
      ],
      rules: const <String>['No leg extension machine.', 'Stop a set if the knee hurts.'],
      tests: const <ProgramTest>[
        ProgramTest(text: 'Single-leg squat, 10 reps, no pain'),
        ProgramTest(text: 'Bike 30 min at an easy pace'),
      ],
    );

/// The active knee program in program week 2 of 4, with session A (slot 1) done and B next.
Program kneeProgram({
  String status = 'active',
  String state = 'running',
  int week = 2,
  List<bool> done = const <bool>[true, false, false, false, false],
  String id = 'prog-1',
}) {
  final Program v = kneeValue();
  const List<String> titles = <String>['Session A', 'Session B', 'Session A', 'Bike', 'Bike'];
  final List<ProgramSlot> slots = <ProgramSlot>[
    for (int i = 0; i < v.week.length; i++) ProgramSlot(slot: i, key: v.week[i], title: titles[i], done: done[i]),
  ];
  final int first = done.indexOf(false);
  final ProgramSession? s = first < 0 ? null : v.phases[week - 1].sessions.firstWhere((ProgramSession x) => x.key == v.week[first]);
  return Program(
    programId: id,
    title: v.title,
    purpose: v.purpose,
    status: status,
    startsOn: v.startsOn,
    endsOn: v.endsOn,
    week: v.week,
    phases: v.phases,
    rules: v.rules,
    tests: const <ProgramTest>[
      ProgramTest(testId: 't1', text: 'Single-leg squat, 10 reps, no pain', doneOn: '2026-11-18'),
      ProgramTest(testId: 't2', text: 'Bike 30 min at an easy pace'),
    ],
    rev: 1,
    now: ProgramNow(
      state: state,
      week: week,
      weeks: 4,
      phaseIndex: week - 1,
      slots: slots,
      next: s == null || state != 'running'
          ? null
          : ProgramNext(slot: first, key: s.key, title: s.title, activity: s.activity, exercises: s.exercises, note: s.note),
    ),
  );
}

Proposal kneeProposal({String status = 'ready', String id = 'p1', String? error, String? targetId}) => Proposal(
      proposalId: id,
      status: status,
      targetId: targetId,
      reason: 'Four weeks, three kinds of day, built around the knee.',
      error: error,
      program: status == 'ready' ? kneeValue() : null,
    );
