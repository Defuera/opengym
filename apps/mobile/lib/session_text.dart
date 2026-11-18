/// Words for a finished session on its recap. Pure Dart.
library;

import 'entry_text.dart';
import 'models.dart';
import 'planner.dart';

/// One entry of an exercise as a line: "8 × 60 kg", "6½ × 70 kg" (the last rep
/// failed), "25 min" or "25 min, 10.9 km".
String setLine(SetEntry s) {
  final double? m = s.minutes;
  if (m != null) {
    return timeText(m, s.distanceKm);
  }
  return '${s.reps}${s.failed ? '½' : ''} × ${fmtKg(s.kg)} kg';
}

/// Whole minutes between start and end, at least 1.
int sessionMinutes(Session s) {
  final int ms = (s.endedAt ?? s.startedAt) - s.startedAt;
  final int m = (ms / 60000).round();
  return m < 1 ? 1 : m;
}

/// Whether the session has real start and end times. An import has not.
bool hasRealTimes(Session s) => s.source != 'import';

/// "17 Nov 2026".
String sessionDate(Session s) => dateText(s.startedAt);

/// "Started 18:05".
String sessionStart(Session s) => 'Started ${clockText(s.startedAt)}';

/// "52 min".
String sessionDuration(Session s) => '${sessionMinutes(s)} min';
