import 'dart:math' as math;

import 'models.dart';
import 'planner.dart';

/// Focus rotation and local proposals from the user's own log. No Flutter imports.

List<Session> gymSessions(List<Session> sessions) {
  return sessions.where((Session s) => s.kind == 'gym').toList();
}

/// Sessions with sets of [activity] (matched by [activityKey]), oldest first.
List<Session> sessionsOf(List<Session> sessions, String activity) {
  final String key = activityKey(activity);
  return gymSessions(sessions).where((Session s) => activityKey(s.type) == key).toList();
}

class FocusRank {
  const FocusRank({required this.focus, required this.at, required this.index});

  final String focus;
  final int at;
  final int index;
}

/// Rotation over the foci the user did for [activity]: least recently done
/// first. Empty when the log has none.
List<FocusRank> focusRotation(List<Session> sessions, {String activity = gymType}) {
  final Map<String, int> last = <String, int>{};
  for (final Session s in sessionsOf(sessions, activity)) {
    final String? f = s.focus;
    if (f != null) {
      last[f] = math.max(last[f] ?? 0, s.endedAt ?? 0);
    }
  }
  final List<String> known = last.keys.toList();
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

/// The foci the user can pick for [activity], the advised one first, then by
/// what is due.
List<String> gymFoci(List<Session> sessions, {String activity = gymType, String? advised}) {
  final List<String> rest = <String>[
    for (final FocusRank r in focusRotation(sessions, activity: activity)) r.focus,
  ];
  if (advised == null || advised.isEmpty) {
    return rest;
  }
  return <String>[advised, ...rest.where((String f) => f != advised)];
}

/// The session type of [activity] done longest ago, when the log has one.
String? advisedActivityFocus(List<Session> sessions, String activity) {
  final String key = activityKey(activity);
  final Map<String, int> last = <String, int>{};
  for (final Session s in sessions) {
    final String? f = s.focus;
    if (s.kind == 'activity' && activityKey(s.type) == key && f != null) {
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
  final String key = activityKey(activity);
  final List<String> out = <String>[];
  for (final Session s in sessions.reversed) {
    final String? f = s.focus;
    if (s.kind == 'activity' && activityKey(s.type) == key && f != null && !out.contains(f)) {
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

/// Local proposals of sessions with sets, in the same shape as the server's.
/// One item per activity in the log (most often first, at most 6): the focus
/// that is due, with the last time. Empty when the log has no such session.
List<Prediction> rankActivities(List<Session> sessions, {int? nowMs}) {
  final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final Map<String, List<Session>> byKey = <String, List<Session>>{};
  for (final Session s in gymSessions(sessions)) {
    byKey.putIfAbsent(activityKey(s.type), () => <Session>[]).add(s);
  }
  final List<List<Session>> groups = byKey.values.toList()
    ..sort((List<Session> a, List<Session> b) {
      if (a.length != b.length) {
        return b.length.compareTo(a.length);
      }
      return _latest(b).compareTo(_latest(a));
    });
  final List<Prediction> out = <Prediction>[];
  for (final List<Session> g in groups.take(6)) {
    final Session last = g.reduce((Session a, Session b) => b.when >= a.when ? b : a);
    final List<FocusRank> rot = focusRotation(g, activity: last.type);
    final String? focus = rot.isEmpty ? null : rot.first.focus;
    final String f = focus == null ? '' : '${focus.toLowerCase()} ';
    final Session seen = g
        .where((Session s) => focus == null || s.focus == focus)
        .reduce((Session a, Session b) => b.when >= a.when ? b : a);
    out.add(Prediction(
      kind: 'gym',
      type: last.type,
      focus: focus,
      reason: 'Last ${f}session was ${_ago(seen.when, now)}',
    ));
  }
  return out;
}

int _latest(List<Session> g) => g.map((Session s) => s.when).reduce(math.max);
