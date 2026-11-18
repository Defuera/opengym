import 'models.dart';
import 'planner.dart';

/// One time/distance activity from the log, for the Log sheet.
class LogActivity {
  const LogActivity({required this.name, required this.count, required this.last});

  /// The most recent spelling in the log.
  final String name;
  final int count;
  final Session last;

  /// "Last: 8 Aug · 13 km", "Last: 9 Nov · 25 min" or "Last: 8 Feb".
  String lastLine() {
    final double? km = last.distanceKm;
    final int? min = last.minutes;
    final String? detail = km != null && km > 0
        ? '${fmtKg(km)} km'
        : (min != null && min > 0 ? '$min min' : null);
    final String date = shortDate(last.when);
    return detail == null ? 'Last: $date' : 'Last: $date · $detail';
  }
}

/// The time/distance activities in [sessions], most often first (ties: most
/// recent first). Names that share an [activityKey] count as one activity.
List<LogActivity> logActivities(List<Session> sessions) {
  final Map<String, List<Session>> byKey = <String, List<Session>>{};
  for (final Session s in sessions) {
    if (s.kind == 'activity' && s.type.trim().isNotEmpty) {
      byKey.putIfAbsent(activityKey(s.type), () => <Session>[]).add(s);
    }
  }
  final List<LogActivity> out = <LogActivity>[];
  for (final List<Session> g in byKey.values) {
    final Session last = g.reduce((Session a, Session b) => b.when >= a.when ? b : a);
    out.add(LogActivity(name: last.type.trim(), count: g.length, last: last));
  }
  out.sort((LogActivity a, LogActivity b) {
    if (a.count != b.count) {
      return b.count.compareTo(a.count);
    }
    return b.last.when.compareTo(a.last.when);
  });
  return out;
}

/// One activity type of the log, for step 1 of the Start tab.
class StartType {
  const StartType({required this.name, required this.hasSets});

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
    rows.add((StartType(name: last.type.trim(), hasSets: last.kind == 'gym'), recent, g.length, last.when));
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
