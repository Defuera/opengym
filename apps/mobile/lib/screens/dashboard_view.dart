import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/consistency_row.dart';
import '../widgets/goal_progress_card.dart';
import '../widgets/note_card.dart';
import '../widgets/session_list_item.dart';
import '../widgets/stat_tile.dart';
import '../widgets/trend_card.dart';

typedef ModuleBuilder = Widget Function(DashboardModule m);

/// Dashboard module type -> widget. A type that is not here is skipped.
/// (`stat` is also listed so it is "known", but stats are laid out two per
/// row by [DashboardView] and use [_stat] for the tile itself.)
final Map<String, ModuleBuilder> moduleBuilders = <String, ModuleBuilder>{
  'stat': _stat,
  'goal_progress': (DashboardModule m) => GoalProgressCard(
        title: m.title,
        current: m.current,
        target: m.target,
        fraction: m.fraction,
      ),
  'trend': (DashboardModule m) => TrendCard(
        title: m.title,
        unit: m.unit,
        values: m.points.map((TrendPoint p) => p.value).toList(),
      ),
  'consistency': (DashboardModule m) =>
      ConsistencyRow(title: m.title, days: m.days),
  'recent_sessions': _recent,
  'note': (DashboardModule m) => NoteCard(text: m.text),
};

Widget _stat(DashboardModule m) {
  return StatTile(label: m.label, value: m.value, highlighted: m.highlighted);
}

Widget _recent(DashboardModule m) {
  final List<Widget> rows = <Widget>[
    Text(m.title.isEmpty ? 'Recent' : m.title, style: OG.display(24)),
    const SizedBox(height: 10),
  ];
  for (final ModuleItem i in m.items) {
    rows.add(SessionListItem(
      title: i.title,
      subtitle: i.subtitle,
      trailing: i.trailing,
    ));
    rows.add(const SizedBox(height: 10));
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
}

/// Renders the server's dashboard modules in order.
class DashboardView extends StatelessWidget {
  const DashboardView({super.key, required this.dashboard, this.recent});

  final Dashboard dashboard;

  /// Replaces the server's `recent_sessions` module: the list the app merged
  /// from sessions and notes by time. When the server sends no such module it
  /// is added at the end. Null keeps the server list as it is.
  final Widget? recent;

  @override
  Widget build(BuildContext context) {
    final List<Widget> out = <Widget>[];
    final List<DashboardModule> mods = dashboard.modules;
    final Widget? mine = recent;
    bool recentUsed = false;
    int i = 0;
    while (i < mods.length) {
      final DashboardModule m = mods[i];
      if (m.type == 'recent_sessions' && mine != null) {
        if (!recentUsed) {
          out.add(mine);
          out.add(const SizedBox(height: 14));
          recentUsed = true;
        }
        i++;
        continue;
      }
      if (m.type == 'stat') {
        final List<Widget> row = <Widget>[Expanded(child: _stat(m))];
        if (i + 1 < mods.length && mods[i + 1].type == 'stat') {
          row.add(const SizedBox(width: 12));
          row.add(Expanded(child: _stat(mods[i + 1])));
          i++;
        } else {
          row.add(const SizedBox(width: 12));
          row.add(const Expanded(child: SizedBox()));
        }
        out.add(Row(children: row));
      } else {
        final ModuleBuilder? b = moduleBuilders[m.type];
        if (b != null) {
          out.add(b(m));
        }
      }
      out.add(const SizedBox(height: 14));
      i++;
    }
    if (mine != null && !recentUsed) {
      out.add(mine);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }
}
