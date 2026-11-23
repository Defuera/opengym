import 'package:opengym/models.dart';
import 'package:opengym/planner.dart';

/// 23 November 2026, 12:00 local. The ski goal is dated 19 December: 26 days.
final int homeNow = DateTime(2026, 11, 23, 12).millisecondsSinceEpoch;

int homeAgo(double days) => homeNow - (days * dayMs).round();

Session homeGym(String id, double daysAgo, String focus, Map<String, double> tops) => Session(
      id: id,
      kind: 'gym',
      type: 'Gym',
      focus: focus,
      startedAt: homeAgo(daysAgo) - 3600000,
      endedAt: homeAgo(daysAgo),
      exercises: <Exercise>[
        for (final MapEntry<String, double> e in tops.entries)
          Exercise(id: '$id-${e.key}', name: e.key, sets: <SetEntry>[SetEntry(reps: 10, kg: e.value, done: true)]),
      ],
    );

/// Five sessions in the last seven days, the last one yesterday, and one
/// older session that gives the "before" values.
List<Session> homeSessions() => <Session>[
      homeGym('old', 10, 'Legs', <String, double>{'Leg Press': 20, 'Hip Adduction': 30, 'Row': 40}),
      homeGym('s1', 6, 'Upper', <String, double>{'Row': 40, 'Bench Press': 45}),
      homeGym('s2', 5, 'Legs', <String, double>{'Leg Press': 25, 'Hip Adduction': 32}),
      homeGym('s3', 3, 'Upper', <String, double>{'Row': 42, 'Bench Press': 47.5}),
      homeGym('s4', 2, 'Legs', <String, double>{'Leg Press': 30, 'Hip Adduction': 35}),
      homeGym('s5', 1, 'Legs', <String, double>{'Leg Press': 35, 'Hip Adduction': 40}),
    ];

final Goal skiGoal = Goal(
  id: 'g-ski',
  title: 'Top priority: legs and knees ready to ski on 19 December 2026',
  kind: 'custom',
  status: 'active',
  source: 'ai',
  createdAt: homeAgo(21),
);

final Goal weeklyGoal = Goal(
  id: 'g-week',
  title: 'Train 5 times a week',
  kind: 'consistency',
  status: 'active',
  source: 'user',
  createdAt: homeAgo(30),
  sessionsPerWeek: 5,
);

const Review homeReview = Review(
  sessionId: 's5',
  source: 'ai',
  summary: 'Leg Press went up to 35 kg, the best this month. Knees stayed quiet through all sets, so next time add a '
      'set of Hip Adduction before you raise the load again.',
);

/// What the server sends for the same data: the modules the new blocks cover
/// plus a note.
const Dashboard homeDashboard = Dashboard(days: 7, source: 'rules', modules: <DashboardModule>[
  DashboardModule(type: 'goal_progress', goalId: 'g-ski', title: 'Top priority', current: 'In progress', target: 'Target'),
  DashboardModule(type: 'stat', label: 'Sessions, 7 days', value: '5', highlighted: true),
  DashboardModule(type: 'stat', label: 'Active days', value: '5'),
  DashboardModule(type: 'consistency', title: 'Active days', days: <bool>[true, true, false, true, true, true, true]),
  DashboardModule(type: 'goal_progress', goalId: 'g-week', title: 'Train 5 times a week', current: '5', target: '5 / week', fraction: 1),
  DashboardModule(type: 'trend', title: 'Leg Press, top set', unit: 'kg', points: <TrendPoint>[TrendPoint(t: 1, value: 20), TrendPoint(t: 2, value: 35)]),
  DashboardModule(type: 'note', text: 'Rest the knees on Sunday.'),
  DashboardModule(type: 'recent_sessions', items: <ModuleItem>[ModuleItem(title: 'Server row', subtitle: 'x', trailing: 'y')]),
]);
