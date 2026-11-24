import 'models.dart';
import 'planner.dart';

/// An activity counts as current when it was done in the last [recentDays]
/// days. The Start list shows the current ones; the rest is under "More".
const int recentDays = 60;

bool usedRecently(int lastWhen, {int? nowMs}) =>
    lastWhen >= (nowMs ?? DateTime.now().millisecondsSinceEpoch) - recentDays * dayMs;

/// Splits [all] into the rows shown at once and the rows under "More". With no
/// current row, everything is shown.
(List<T>, List<T>) splitCurrent<T>(List<T> all, bool Function(T) current) {
  final List<T> now = all.where(current).toList();
  if (now.isEmpty) {
    return (all, <T>[]);
  }
  return (now, all.where((T x) => !current(x)).toList());
}

/// One activity type of the log, for step 1 of the Start tab.
class StartType {
  const StartType({required this.name, required this.hasSets, this.lastWhen = 0});

  /// The time of the latest session of this type.
  final int lastWhen;

  /// The most recent spelling in the log.
  final String name;

  /// True for a session with sets (`kind: gym`), false for time/distance.
  final bool hasSets;
}

/// The vocabulary of the log, both kinds: sessions with sets (any name) and
/// time/distance activities. Names that share an [activityKey] count as one;
/// the kind is the one of the latest session. Most used in the last 60 days
/// first, then most used overall, then most recent (the same order the server
/// uses for its ranking).
List<StartType> startTypes(List<Session> sessions, {int? nowMs}) {
  final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final int from = now - 60 * dayMs;
  final Map<String, List<Session>> byKey = <String, List<Session>>{};
  for (final Session s in sessions) {
    if (s.type.trim().isNotEmpty) {
      byKey.putIfAbsent(activityKey(s.type), () => <Session>[]).add(s);
    }
  }
  final List<(StartType, int, int, int)> rows = <(StartType, int, int, int)>[];
  for (final List<Session> g in byKey.values) {
    final Session last = g.reduce((Session a, Session b) => b.when >= a.when ? b : a);
    final int recent = g.where((Session s) => s.when >= from).length;
    rows.add((StartType(name: last.type.trim(), hasSets: last.kind == 'gym', lastWhen: last.when), recent, g.length, last.when));
  }
  rows.sort(((StartType, int, int, int) a, (StartType, int, int, int) b) {
    if (a.$2 != b.$2) {
      return b.$2.compareTo(a.$2);
    }
    if (a.$3 != b.$3) {
      return b.$3.compareTo(a.$3);
    }
    return b.$4.compareTo(a.$4);
  });
  return <StartType>[for (final (StartType, int, int, int) r in rows) r.$1];
}
