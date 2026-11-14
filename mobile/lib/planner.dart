import 'dart:math' as math;

import 'models.dart';

/// Planning rules in plain code. No Flutter imports. Every function takes the
/// session list as an argument.

const Map<String, List<String>> starterTemplates = <String, List<String>>{
  'Push': <String>['Bench press', 'Overhead press', 'Dips', 'Triceps pushdown'],
  'Pull': <String>['Pull-up', 'Barbell row', 'Lat pulldown', 'Biceps curl'],
  'Legs': <String>['Squat', 'Romanian deadlift', 'Leg press', 'Calf raise'],
};

/// Starter order, used as the tie-break for predictions.
const List<String> starterTypes = <String>['Push', 'Pull', 'Legs'];

const List<String> exerciseLibrary = <String>[
  'Bench press',
  'Incline bench press',
  'Overhead press',
  'Dips',
  'Triceps pushdown',
  'Lateral raise',
  'Pull-up',
  'Barbell row',
  'Lat pulldown',
  'Face pull',
  'Biceps curl',
  'Squat',
  'Deadlift',
  'Romanian deadlift',
  'Leg press',
  'Leg curl',
  'Leg extension',
  'Calf raise',
  'Plank',
];

const List<String> activities = <String>['Run', 'Walk', 'Cycle', 'Swim', 'Other'];

const int dayMs = 86400000;

final math.Random _rng = math.Random();

String newId() {
  final String a = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final String b = _rng.nextInt(1679616).toRadixString(36);
  return a + b;
}

List<Session> gymSessions(List<Session> sessions) {
  return sessions.where((Session s) => s.kind == 'gym').toList();
}

List<SetEntry>? lastSetsFor(List<Session> sessions, String name) {
  for (int i = sessions.length - 1; i >= 0; i--) {
    final Session s = sessions[i];
    if (s.kind != 'gym') {
      continue;
    }
    for (final Exercise e in s.exercises) {
      if (e.name == name && e.sets.isNotEmpty) {
        return e.sets
            .map((SetEntry x) => SetEntry(reps: x.reps, kg: x.kg, isMax: x.isMax))
            .toList();
      }
    }
  }
  return null;
}

List<SetEntry> defaultSets(String name) {
  if (name == 'Bench press') {
    return <SetEntry>[
      SetEntry(reps: 6, kg: 20),
      SetEntry(reps: 6, kg: 40),
      SetEntry(reps: 6, kg: 60),
      SetEntry(reps: 1, kg: 60, isMax: true),
    ];
  }
  return <SetEntry>[
    SetEntry(reps: 8, kg: 0),
    SetEntry(reps: 8, kg: 0),
    SetEntry(reps: 8, kg: 0),
  ];
}

Exercise makeExercise(List<Session> sessions, String name) {
  final List<SetEntry>? last = lastSetsFor(sessions, name);
  final bool fresh = last == null && name != 'Bench press';
  return Exercise(
    id: newId(),
    name: name,
    sets: last ?? defaultSets(name),
    fresh: fresh,
    carry: fresh,
  );
}

List<Exercise> planFor(List<Session> sessions, String type) {
  final List<Session> g = gymSessions(sessions);
  List<String>? names;
  for (int i = g.length - 1; i >= 0; i--) {
    if (g[i].type == type) {
      names = g[i].exercises.map((Exercise e) => e.name).toList();
      break;
    }
  }
  final List<String> use = (names != null && names.isNotEmpty)
      ? names
      : (starterTemplates[type] ?? const <String>[]);
  return use.map((String n) => makeExercise(sessions, n)).toList();
}

class Prediction {
  const Prediction({required this.type, required this.at, required this.index});

  final String type;
  final int at;
  final int index;
}

/// Rotation: least recently done first, ties by starter order.
List<Prediction> predictions(List<Session> sessions) {
  final Map<String, int> last = <String, int>{};
  for (final Session s in gymSessions(sessions)) {
    last[s.type] = s.endedAt ?? 0;
  }
  final List<Prediction> out = <Prediction>[];
  for (int i = 0; i < starterTypes.length; i++) {
    final String t = starterTypes[i];
    out.add(Prediction(type: t, at: last[t] ?? 0, index: i));
  }
  out.sort((Prediction a, Prediction b) {
    if (a.at != b.at) {
      return a.at.compareTo(b.at);
    }
    return a.index.compareTo(b.index);
  });
  return out;
}

class StatsResult {
  const StatsResult({
    required this.sessions,
    required this.delta,
    required this.days,
    required this.sets,
    this.best,
    this.top,
  });

  final int sessions;
  final int delta;
  final int days;
  final int sets;
  final String? best;
  final double? top;
}

StatsResult stats(List<Session> sessions, int days, {int? nowMs}) {
  final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final int from = now - days * dayMs;
  final int prev = from - days * dayMs;
  int cur = 0;
  int before = 0;
  int sets = 0;
  final Set<String> dayKeys = <String>{};
  final Map<String, int> count = <String, int>{};
  final Map<String, double> top = <String, double>{};
  for (final Session s in sessions) {
    final int? end = s.endedAt;
    if (end == null) {
      continue;
    }
    if (end >= from) {
      cur++;
      final DateTime d = DateTime.fromMillisecondsSinceEpoch(end);
      dayKeys.add('${d.year}-${d.month}-${d.day}');
      for (final Exercise e in s.exercises) {
        for (final SetEntry x in e.sets) {
          sets++;
          count[e.name] = (count[e.name] ?? 0) + 1;
          top[e.name] = math.max(top[e.name] ?? 0.0, x.kg);
        }
      }
    } else if (end >= prev) {
      before++;
    }
  }
  String? best;
  int bestCount = 0;
  for (final MapEntry<String, int> en in count.entries) {
    if (en.value > bestCount) {
      best = en.key;
      bestCount = en.value;
    }
  }
  final String? b = best;
  return StatsResult(
    sessions: cur,
    delta: cur - before,
    days: dayKeys.length,
    sets: sets,
    best: b,
    top: b == null ? null : top[b],
  );
}

bool allDone(Exercise e) {
  return e.sets.isNotEmpty && e.sets.every((SetEntry s) => s.done);
}

int firstOpen(Exercise? e) {
  if (e == null) {
    return 0;
  }
  final int i = e.sets.indexWhere((SetEntry s) => !s.done);
  return i < 0 ? 0 : i;
}

String fmtKg(double k) {
  final double r = (k * 10).round() / 10;
  if (r == r.truncateToDouble()) {
    return r.toInt().toString();
  }
  return r.toString();
}

String whenLabel(int t, {int? nowMs}) {
  final DateTime n = DateTime.fromMillisecondsSinceEpoch(
    nowMs ?? DateTime.now().millisecondsSinceEpoch,
  );
  final DateTime a = DateTime.fromMillisecondsSinceEpoch(t);
  final DateTime today = DateTime.utc(n.year, n.month, n.day);
  final DateTime day = DateTime.utc(a.year, a.month, a.day);
  final int d = today.difference(day).inDays;
  if (d <= 0) {
    return 'Today';
  }
  if (d == 1) {
    return 'Yesterday';
  }
  return '$d days ago';
}
