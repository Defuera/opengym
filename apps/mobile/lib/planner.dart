import 'dart:math' as math;

import 'focus.dart';
import 'models.dart';

export 'focus.dart';

/// Planning rules in plain code. No Flutter imports. Every function takes the
/// session list as an argument.

const int dayMs = 86400000;

final math.Random _rng = math.Random();

String newId() {
  final String a = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final String b = _rng.nextInt(1679616).toRadixString(36);
  return a + b;
}

/// The most recent logged exercise of that name (exact spelling) with entries.
Exercise? lastExerciseFor(List<Session> sessions, String name) {
  for (int i = sessions.length - 1; i >= 0; i--) {
    final Session s = sessions[i];
    if (s.kind != 'gym') {
      continue;
    }
    for (final Exercise e in s.exercises) {
      if (e.name == name && e.sets.isNotEmpty) {
        return e;
      }
    }
  }
  return null;
}

/// Fresh (not done) copies of the sets of the last time [name] was logged.
/// Works for a time exercise too: the copies are time entries.
List<SetEntry>? lastSetsFor(List<Session> sessions, String name) {
  return lastExerciseFor(sessions, name)?.sets.map((SetEntry x) => x.copy()).toList();
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

/// Minutes a new time exercise starts with, until the user sets it.
const double defaultMinutes = 20;

/// The longest text of an activity log (ADR-018); the server takes the same.
const int maxLogTextLength = 1000;

/// A fresh exercise for a session. A name from the log keeps the measure and
/// the entries of its last time. A new name uses [measure] (default sets).
Exercise makeExercise(List<Session> sessions, String name, {String measure = measureSets}) {
  final Exercise? last = lastExerciseFor(sessions, name);
  if (last != null) {
    return Exercise(
      id: newId(),
      name: name,
      measure: last.measure,
      sets: last.sets.map((SetEntry x) => x.copy()).toList(),
    );
  }
  if (measure == measureTime) {
    return Exercise(
      id: newId(),
      name: name,
      measure: measureTime,
      sets: <SetEntry>[SetEntry.time(defaultMinutes)],
    );
  }
  final bool fresh = name != 'Bench press';
  return Exercise(
    id: newId(),
    name: name,
    sets: defaultSets(name),
    fresh: fresh,
    carry: fresh,
  );
}

/// An exercise of the user's log: the spelling and the measure of its latest entry.
class LoggedExercise {
  const LoggedExercise(this.name, this.measure);

  final String name;
  final String measure;
}

/// The key two exercise names match by: lower case, trimmed, inner spaces collapsed.
String exerciseKey(String name) => name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// The exercises of the whole log, most recently used first, in the spelling
/// of their latest use. Nothing else: the vocabulary comes from the log (ADR-016).
List<LoggedExercise> loggedExercises(List<Session> sessions) {
  final List<Session> byTime = List<Session>.of(sessions.where((Session s) => s.kind == 'gym'))
    ..sort((Session a, Session b) => b.when.compareTo(a.when));
  final Set<String> seen = <String>{};
  final List<LoggedExercise> out = <LoggedExercise>[];
  for (final Session s in byTime) {
    for (final Exercise e in s.exercises.reversed) {
      final String n = e.name.trim();
      if (n.isNotEmpty && seen.add(exerciseKey(n))) {
        out.add(LoggedExercise(n, e.measure));
      }
    }
  }
  return out;
}

/// A time entry as text: "25 min" or "25 min, 10.9 km".
String timeText(double minutes, [double? distanceKm]) {
  final String m = '${fmtKg(minutes)} min';
  return distanceKm == null ? m : '$m, ${fmtKg(distanceKm)} km';
}

bool _sameFocus(String? a, String? b) => activityKey(a ?? '') == activityKey(b ?? '');

/// The local fallback plan: repeat the user's last session of the same
/// [activity] and [focus]. With none, an empty plan (no starter templates).
List<Exercise> planFor(List<Session> sessions, String activity, String? focus) {
  final List<Session> g = sessionsOf(sessions, activity);
  for (int i = g.length - 1; i >= 0; i--) {
    if (_sameFocus(g[i].focus, focus) && g[i].exercises.isNotEmpty) {
      return g[i].exercises.map((Exercise e) => makeExercise(sessions, e.name, measure: e.measure)).toList();
    }
  }
  return <Exercise>[];
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
        // A time entry is not a set: it counts for nothing here.
        for (final SetEntry x in e.sets.where((SetEntry x) => !x.isTime)) {
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
