import 'package:flutter/material.dart';

import '../entry_text.dart';
import '../models.dart';
import '../planner.dart';
import '../theme.dart';
import '../widgets/entry_list_item.dart';
import '../widgets/session_list_item.dart';

/// One row of the recent list: a session or a note, with the time it is about.
class RecentItem {
  const RecentItem._(this.at, this.session, this.entry);

  RecentItem.session(Session s) : this._(s.when, s, null);
  RecentItem.entry(LogEntry e) : this._(e.at, null, e);

  final int at;
  final Session? session;
  final LogEntry? entry;
}

/// Sessions and notes in one list, newest first by time (a session by its end,
/// a note by `at`). The sessions keep the order of [sessions], which is oldest
/// first, so the newest is read from the end; the notes are sorted by `at`.
/// The two lines are merged by time. A tie puts the note first. Keeps the
/// first [limit].
List<RecentItem> mergeRecent(List<Session> sessions, List<LogEntry> entries, {int limit = 5}) {
  final List<LogEntry> notes = List<LogEntry>.of(entries)
    ..sort((LogEntry a, LogEntry b) => b.at.compareTo(a.at));
  final List<RecentItem> out = <RecentItem>[];
  int s = sessions.length - 1;
  int n = 0;
  while (out.length < limit && (s >= 0 || n < notes.length)) {
    final bool takeNote = s < 0 || (n < notes.length && notes[n].at >= sessions[s].when);
    out.add(takeNote ? RecentItem.entry(notes[n++]) : RecentItem.session(sessions[s--]));
  }
  return out;
}

/// The "Recent" block of Home. [onOpenEntry] opens a note.
class HomeRecent extends StatelessWidget {
  const HomeRecent({
    super.key,
    required this.sessions,
    required this.entries,
    this.onOpenEntry,
    this.onOpenSession,
    this.title = 'Recent',
  });

  final List<Session> sessions;
  final List<LogEntry> entries;
  final ValueChanged<LogEntry>? onOpenEntry;

  /// Opens the recap of a finished session.
  final ValueChanged<Session>? onOpenSession;
  final String title;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[
      Text(title, style: OG.display(24)),
      const SizedBox(height: 10),
    ];
    for (final RecentItem r in mergeRecent(sessions, entries)) {
      final LogEntry? e = r.entry;
      rows.add(e != null
          ? EntryListItem(
              title: entryTitle(e),
              subtitle: entryWhen(e.at),
              attachments: e.files.length,
              onTap: onOpenEntry == null ? null : () => onOpenEntry!(e),
            )
          : _session(r.session!));
      rows.add(const SizedBox(height: 10));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _session(Session s) {
    int n = 0;
    double min = 0;
    double km = 0;
    for (final Exercise e in s.exercises) {
      if (e.isTime) {
        for (final SetEntry x in e.sets) {
          min += x.minutes ?? 0;
          km += x.distanceKm ?? 0;
        }
      } else {
        n += e.sets.length;
      }
    }
    final bool gym = s.kind == 'gym';
    final String timed = min > 0 ? timeText(min, km > 0 ? km : null) : '';
    return SessionListItem(
      title: s.type,
      tag: s.focus,
      subtitle: whenLabel(s.endedAt ?? s.startedAt),
      onTap: onOpenSession == null ? null : () => onOpenSession!(s),
      trailing: gym ? _gymTrailing(n, timed) : _activityTrailing(s),
    );
  }

  /// "8 sets", "25 min, 10.9 km" or both.
  String _gymTrailing(int sets, String timed) {
    if (timed.isEmpty) {
      return '$sets sets';
    }
    return sets == 0 ? timed : '$sets sets, $timed';
  }

  String _activityTrailing(Session s) {
    final double? km = s.distanceKm;
    if (s.minutes == null && km != null) {
      return '${fmtKg(km)} km';
    }
    return '${s.minutes ?? 0} min';
  }
}
