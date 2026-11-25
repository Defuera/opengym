import '../models.dart';
import 'tracker_source.dart';

/// Pure mapping from a finished session to the one workout Gym Days writes
/// to the phone's health store (ADR-036).

/// The most a written session may last. A longer one is a mistake (a session
/// left open), and the store would hold a wrong day.
const Duration writeLongest = Duration(hours: 12);

/// The kind of workout, from the activity name first ("Run", "Cycling"), then
/// from the shape: a session with sets is strength training. Anything else is
/// [WorkoutKind.other].
WorkoutKind workoutKindFor(Session s) {
  final String name = s.type.toLowerCase();
  bool has(List<String> parts) => parts.any(name.contains);
  if (has(<String>['run', 'jog'])) {
    return WorkoutKind.running;
  }
  if (has(<String>['walk'])) {
    return WorkoutKind.walking;
  }
  if (has(<String>['cycl', 'bike', 'biking', 'ride'])) {
    return WorkoutKind.cycling;
  }
  if (has(<String>['swim'])) {
    return WorkoutKind.swimming;
  }
  if (has(<String>['hik'])) {
    return WorkoutKind.hiking;
  }
  if (has(<String>['row'])) {
    return WorkoutKind.rowing;
  }
  if (has(<String>['yoga'])) {
    return WorkoutKind.yoga;
  }
  if (has(<String>['gym', 'strength', 'weight', 'lift'])) {
    return WorkoutKind.strength;
  }
  final bool hasSets = s.exercises.any((Exercise e) => !e.isTime && e.sets.any((SetEntry x) => x.done));
  return hasSets ? WorkoutKind.strength : WorkoutKind.other;
}

/// The distance of a session: its own, or the sum of the time sets. Null when none.
double? sessionDistanceKm(Session s) {
  final double? own = s.distanceKm;
  if (own != null && own > 0) {
    return own;
  }
  double sum = 0;
  for (final Exercise e in s.exercises) {
    for (final SetEntry x in e.sets) {
      if (x.done) {
        sum += x.distanceKm ?? 0;
      }
    }
  }
  return sum > 0 ? sum : null;
}

/// The workout to write for a finished session, or null when there is nothing
/// sound to write: no end time, an end not after the start, or a session over
/// [writeLongest]. A session logged as one text has no real times (start and
/// end are the same moment), so it gives null.
WorkoutWrite? workoutWriteFor(Session s) {
  final int? end = s.endedAt;
  if (end == null || end <= s.startedAt) {
    return null;
  }
  final DateTime start = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
  final DateTime stop = DateTime.fromMillisecondsSinceEpoch(end);
  if (stop.difference(start) > writeLongest) {
    return null;
  }
  final String focus = (s.focus ?? '').trim();
  return WorkoutWrite(
    kind: workoutKindFor(s),
    title: focus.isEmpty ? s.type : '${s.type} $focus',
    start: start,
    end: stop,
    distanceKm: sessionDistanceKm(s),
  );
}
