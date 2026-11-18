import 'package:flutter/material.dart';

import '../models.dart';
import '../planner.dart';
import '../theme.dart';
import '../widgets/note_box.dart';
import '../widgets/stat_tile.dart';
import 'home_recent.dart';

/// Stats tiles, comparison line and the recent list (or the empty state).
class HomeSummary extends StatelessWidget {
  const HomeSummary({
    super.key,
    required this.sessions,
    required this.period,
    this.entries = const <LogEntry>[],
    this.onOpenEntry,
    this.onOpenSession,
  });

  final List<Session> sessions;
  final int period;

  /// Notes. They join the recent list, by time.
  final List<LogEntry> entries;
  final ValueChanged<LogEntry>? onOpenEntry;
  final ValueChanged<Session>? onOpenSession;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty && entries.isNotEmpty) {
      return HomeRecent(
        sessions: sessions,
        entries: entries,
        onOpenEntry: onOpenEntry,
        onOpenSession: onOpenSession,
      );
    }
    if (sessions.isEmpty) {
      return const NoteBox(
        title: 'Nothing logged yet.',
        message: 'Press Start session or Log. '
            'Your stats build from what you log.',
      );
    }
    final StatsResult st = stats(sessions, period);
    final String? best = st.best;
    final String sign = st.delta > 0 ? '+' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: StatTile(label: 'Sessions', value: '${st.sessions}')),
          const SizedBox(width: 12),
          Expanded(
            child: StatTile(label: 'Active days', value: '${st.days} / $period'),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: <Widget>[
          Expanded(
            child: StatTile(
              label: best != null ? '$best top set' : 'Top set',
              value: best != null ? '${fmtKg(st.top ?? 0)} kg' : '–',
              highlighted: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: StatTile(label: 'Sets logged', value: '${st.sets}')),
        ]),
        const SizedBox(height: 18),
        Text(
          'Compared with the ${period == 7 ? 'week' : 'month'} before: '
          '$sign${st.delta} sessions',
          style: OG.muted(),
        ),
        const SizedBox(height: 18),
        HomeRecent(
        sessions: sessions,
        entries: entries,
        onOpenEntry: onOpenEntry,
        onOpenSession: onOpenSession,
      ),
      ],
    );
  }
}
