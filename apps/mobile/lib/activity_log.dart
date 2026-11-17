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
