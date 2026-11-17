import 'package:flutter/material.dart';

import '../models.dart';
import '../planner.dart';
import '../theme.dart';
import '../widgets/note_box.dart';
import '../widgets/session_list_item.dart';
import '../widgets/stat_tile.dart';

/// Stats tiles, comparison line and the recent list (or the empty state).
class HomeSummary extends StatelessWidget {
  const HomeSummary({super.key, required this.sessions, required this.period});

  final List<Session> sessions;
  final int period;

  @override
  Widget build(BuildContext context) {
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
    final List<Widget> recent = <Widget>[];
    for (final Session s in sessions.reversed.take(5)) {
      recent.add(_item(s));
      recent.add(const SizedBox(height: 10));
    }
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
        Text('Recent', style: OG.display(24)),
        const SizedBox(height: 10),
        ...recent,
      ],
    );
  }

  Widget _item(Session s) {
    int n = 0;
    for (final Exercise e in s.exercises) {
      n += e.sets.length;
    }
    final bool gym = s.kind == 'gym';
    return SessionListItem(
      title: s.type,
      tag: s.focus,
      subtitle: whenLabel(s.endedAt ?? s.startedAt),
      trailing: gym ? '$n sets' : _activityTrailing(s),
    );
  }

  String _activityTrailing(Session s) {
    final double? km = s.distanceKm;
    if (s.minutes == null && km != null) {
      return '${fmtKg(km)} km';
    }
    return '${s.minutes ?? 0} min';
  }
}
