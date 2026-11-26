import 'package:flutter/material.dart';

import '../home_data.dart';
import '../models.dart';
import '../planner.dart';
import '../widgets/last_review_card.dart';
import '../widgets/moved_card.dart';
import '../widgets/note_box.dart';
import '../widgets/road_card.dart';
import '../widgets/week_card.dart';
import 'dashboard_view.dart';
import 'home_recent.dart';

/// The Home blocks, top to bottom: This week, Road to (one per dated goal),
/// Last review, What moved, the other server modules, Recent. Everything but
/// the server modules comes from data the app already holds.
class HomeSummary extends StatelessWidget {
  const HomeSummary({
    super.key,
    required this.sessions,
    required this.period,
    this.goals = const <Goal>[],
    this.dashboard,
    this.review,
    this.entries = const <LogEntry>[],
    this.onOpenEntry,
    this.onOpenSession,
    this.nowMs,
  });

  final List<Session> sessions;

  /// 7 or 30.
  final int period;
  final List<Goal> goals;

  /// The server dashboard; null when offline.
  final Dashboard? dashboard;
  final Review? review;

  /// Notes. They join the recent list, by time.
  final List<LogEntry> entries;
  final ValueChanged<LogEntry>? onOpenEntry;
  final ValueChanged<Session>? onOpenSession;

  /// The clock; null is the real time.
  final int? nowMs;

  Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 14), child: w);

  Widget _week(int now) {
    final int? perWeek = weeklyTarget(goals);
    final int? target = perWeek == null ? null : (period == 7 ? perWeek : (perWeek * period / 7).round());
    final StatsResult st = stats(sessions, period, nowMs: now);
    final List<bool> days = activeDays(sessions, period, now);
    final int n = days.length;
    final String unit = st.sessions == 1 && target == null ? 'session' : 'sessions';
    final String head = target == null ? '${st.sessions} $unit' : '${st.sessions} of $target sessions';
    final Session? last = lastSession(sessions);
    final String sign = st.delta > 0 ? '+' : '';
    return WeekCard(
      title: period == 7 ? 'This week' : 'This month',
      headline: head,
      days: days,
      dayLetters: period == 7 ? dayLetters(n, now) : const <String>[],
      lines: period == 7
          ? const <String>[]
          : <String>[
              'Active days ${days.where((bool d) => d).length} / $n',
              '$sign${st.delta} sessions against the month before',
            ],
      last: last == null ? null : lastLine(last, now),
    );
  }

  Widget _road(Goal g, DateTime date, int now) {
    DashboardModule? prog;
    for (final DashboardModule m in dashboard?.modules ?? const <DashboardModule>[]) {
      if (m.type == 'goal_progress' && m.goalId == g.id && m.fraction != null) {
        prog = m;
      }
    }
    final int n = sessionsSince(sessions, g.createdAt);
    return RoadCard(
      title: g.title,
      daysLeft: daysLeftText(daysLeft(date, now)),
      elapsed: elapsedFraction(g.createdAt, date, now),
      sessionsText: '$n ${n == 1 ? 'session' : 'sessions'} so far',
      progress: prog?.fraction,
      progressCurrent: prog?.current,
      progressTarget: prog?.target,
    );
  }

  Widget? _review(int now) {
    final Review? r = review;
    if (r == null || r.text.trim().isEmpty) {
      return null;
    }
    Session? s;
    for (final Session x in sessions) {
      if (x.id == r.sessionId) {
        s = x;
      }
    }
    if (s == null) {
      return null;
    }
    final Session found = s;
    return LastReviewCard(
      session: '${sessionName(found)} · ${whenLabel(found.when, nowMs: now).toLowerCase()}',
      summary: r.text,
      onTap: onOpenSession == null ? null : () => onOpenSession!(found),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final List<(Goal, DateTime)> roads = datedGoals(goals);
    if (sessions.isEmpty && entries.isEmpty && roads.isEmpty) {
      return const NoteBox(
        title: 'Nothing logged yet.',
        message: 'Press Start session or Log. '
            'Your stats build from what you log.',
      );
    }
    final Widget? rev = _review(now);
    final List<MovedRow> moved = whatMoved(sessions, period, now);
    final Dashboard? dash = dashboard;
    final Dashboard? extras = dash == null ? null : homeExtras(dash, goals);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (sessions.isNotEmpty) _gap(_week(now)),
        for (final (Goal, DateTime) r in roads) _gap(_road(r.$1, r.$2, now)),
        if (rev != null) _gap(rev),
        if (moved.isNotEmpty) _gap(MovedCard(rows: moved)),
        if (extras != null && extras.modules.isNotEmpty) DashboardView(dashboard: extras),
        if (sessions.isNotEmpty || entries.isNotEmpty)
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
