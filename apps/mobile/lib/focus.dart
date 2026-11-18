import 'dart:math' as math;

import 'models.dart';

/// Focus rotation from the user's own log. No Flutter imports.

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
