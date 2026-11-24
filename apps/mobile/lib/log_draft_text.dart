/// Words for a log draft in the chat. Pure Dart.
library;

import 'entry_text.dart';
import 'models.dart';
import 'planner.dart';

/// The labelled rows under the summary of a draft: the session, the goal and
/// the limit as separate rows (Exercise, Target, Per week; Body part, Avoid),
/// and the note, only for the parts the draft holds. A note that only says
/// what the summary says is not repeated.
List<(String, String)> logDraftRows(LogDraft d) {
  final LogDraftSession? s = d.session;
  return <(String, String)>[
    if (s != null) ('Session', _sessionLine(s)),
    ...d.goalRows,
    ...d.limitRows,
    if (d.note != null && d.note!.trim().isNotEmpty && d.note!.trim() != d.summary.trim()) ('Note', d.note!.trim()),
  ];
}

/// "Run, easy · 45 min · 8 km".
String _sessionLine(LogDraftSession s) {
  final String focus = (s.focus ?? '').trim();
  final int? min = s.minutes;
  final double? km = s.distanceKm;
  return <String>[
    focus.isEmpty ? s.type : '${s.type}, $focus',
    if (min != null && min > 0) '$min min',
    if (km != null && km > 0) '${fmtKg(km)} km',
  ].where((String p) => p.trim().isNotEmpty).join(' · ');
}

/// "Today, 19:30". A goal, limit or note draft has no time (it makes no entry): null.
String? logDraftWhen(LogDraft d, {int? nowMs}) => d.noEntry ? null : entryWhen(d.at, nowMs: nowMs);
