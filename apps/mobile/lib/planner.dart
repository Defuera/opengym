import 'dart:math' as math;

import 'models.dart';

/// Planning rules in plain code. No Flutter imports. Every function takes the
/// session list as an argument.

const Map<String, List<String>> starterTemplates = <String, List<String>>{
  'Push': <String>['Bench press', 'Overhead press', 'Dips', 'Triceps pushdown'],
  'Pull': <String>['Pull-up', 'Barbell row', 'Lat pulldown', 'Biceps curl'],
  'Legs': <String>['Squat', 'Romanian deadlift', 'Leg press', 'Calf raise'],
};

/// Gym foci offered before the log has any. Starter order breaks ties.
const List<String> starterFoci = <String>['Push', 'Pull', 'Legs'];

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

/// The plan for a gym [focus]: repeat the last gym session with that focus,
/// else the starter template. No focus gives an empty plan.
List<Exercise> planFor(List<Session> sessions, String? focus) {
  final List<Session> g = gymSessions(sessions);
  List<String>? names;
  for (int i = g.length - 1; i >= 0 && focus != null; i--) {
    if (g[i].focus == focus) {
      names = g[i].exercises.map((Exercise e) => e.name).toList();
      break;
    }
  }
  final List<String> use = (names != null && names.isNotEmpty)
      ? names
      : (starterTemplates[focus] ?? const <String>[]);
  return use.map((String n) => makeExercise(sessions, n)).toList();
}

class FocusRank {
  const FocusRank({required this.focus, required this.at, required this.index});

  final String focus;
  final int at;
  final int index;
}

/// Rotation over the gym foci in the log: least recently done first. The
/// starter foci are used only while the log has no gym focus.
List<FocusRank> focusRotation(List<Session> sessions) {
  final Map<String, int> last = <String, int>{};
  for (final Session s in gymSessions(sessions)) {
    final String? f = s.focus;
    if (f != null) {
      last[f] = math.max(last[f] ?? 0, s.endedAt ?? 0);
    }
  }
  final List<String> known = last.isEmpty ? starterFoci : last.keys.toList();
  final List<FocusRank> out = <FocusRank>[
    for (int i = 0; i < known.length; i++)
      FocusRank(focus: known[i], at: last[known[i]] ?? 0, index: i),
  ];
  out.sort((FocusRank a, FocusRank b) {
    if (a.at != b.at) {
      return a.at.compareTo(b.at);
    }
    return a.index.compareTo(b.index);
  });
  return out;
}

/// The gym foci the user can pick, the advised one first, then by what is due.
List<String> gymFoci(List<Session> sessions, {String? advised}) {
  final List<String> rest = <String>[
    for (final FocusRank r in focusRotation(sessions)) r.focus,
  ];
  if (advised == null || advised.isEmpty) {
    return rest;
  }
  return <String>[advised, ...rest.where((String f) => f != advised)];
}

/// The session type of [activity] done longest ago, when the log has one.
String? advisedActivityFocus(List<Session> sessions, String activity) {
  final Map<String, int> last = <String, int>{};
  for (final Session s in sessions) {
    final String? f = s.focus;
    if (s.kind == 'activity' && s.type == activity && f != null) {
      last[f] = math.max(last[f] ?? 0, s.endedAt ?? 0);
    }
  }
  String? best;
  for (final MapEntry<String, int> e in last.entries) {
    if (best == null || e.value < last[best]!) {
      best = e.key;
    }
  }
  return best;
}

/// The session types logged for [activity], most recent first.
List<String> activityFoci(List<Session> sessions, String activity) {
  final List<String> out = <String>[];
  for (final Session s in sessions.reversed) {
    final String? f = s.focus;
    if (s.kind == 'activity' && s.type == activity && f != null && !out.contains(f)) {
      out.add(f);
    }
  }
  return out;
}

String _ago(int at, int now) {
  final int d = ((now - at) / dayMs).floor();
  if (d <= 0) {
    return 'today';
  }
  return d == 1 ? 'yesterday' : '$d days ago';
}

/// Local ranking of ACTIVITIES, in the same shape as the server's. Gym comes
/// once, with the focus that is due; then the most frequent other activities.
List<Prediction> rankActivities(List<Session> sessions, {int? nowMs}) {
  final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final List<Session> gym = gymSessions(sessions);
  Session? lastGym;
  for (final Session s in gym) {
    if (lastGym == null || (s.endedAt ?? 0) >= (lastGym.endedAt ?? 0)) {
      lastGym = s;
    }
  }
  final String reason;
  if (lastGym == null) {
    reason = 'No gym session logged yet';
  } else {
    final String f = lastGym.focus == null ? 'gym' : lastGym.focus!.toLowerCase();
    reason = 'Last $f session was ${_ago(lastGym.endedAt ?? 0, now)}';
  }
  final List<FocusRank> rot = focusRotation(sessions);
  final List<Prediction> out = <Prediction>[
    Prediction(
      kind: 'gym',
      type: gymType,
      focus: rot.isEmpty ? null : rot.first.focus,
      reason: reason,
    ),
  ];
  final Map<String, int> counts = <String, int>{};
  for (final Session s in sessions) {
    if (s.kind == 'activity') {
      counts[s.type] = (counts[s.type] ?? 0) + 1;
    }
  }
  final List<MapEntry<String, int>> ranked = counts.entries.toList()
    ..sort((MapEntry<String, int> a, MapEntry<String, int> b) {
      return b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key);
    });
  for (final MapEntry<String, int> e in ranked.take(3)) {
    out.add(Prediction(
      kind: 'activity',
      type: e.key,
      focus: advisedActivityFocus(sessions, e.key),
      reason: 'Done ${e.value} time${e.value == 1 ? '' : 's'}',
    ));
  }
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
