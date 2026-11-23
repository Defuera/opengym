import 'models.dart';
import 'planner.dart';
import 'widgets/moved_card.dart';

/// What the Home blocks show, computed from data the app already holds.
/// Every function takes `nowMs`, so tests fix the clock.

const List<String> _months = <String>[
  'january', 'february', 'march', 'april', 'may', 'june', 'july', 'august',
  'september', 'october', 'november', 'december', //
];

int? _month(String s) {
  final String k = s.toLowerCase();
  for (int i = 0; i < 12; i++) {
    if (k == _months[i] || (k.length == 3 && _months[i].startsWith(k)) || (k == 'sept' && i == 8)) {
      return i + 1;
    }
  }
  return null;
}

final RegExp _dayFirst = RegExp(r'\b(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,9})\.?,?\s+(\d{4})\b');
final RegExp _monthFirst = RegExp(r'\b([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b');
final RegExp _iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');

/// A goal has no date field. The date is the one written in its title
/// ("19 December 2026", "December 19, 2026" or "2026-12-19"). Null when the
/// title has none. The result is a date at local midnight.
DateTime? goalDate(String title) {
  final RegExpMatch? a = _dayFirst.firstMatch(title);
  if (a != null) {
    final int? m = _month(a.group(2)!);
    if (m != null) {
      return _valid(int.parse(a.group(3)!), m, int.parse(a.group(1)!));
    }
  }
  final RegExpMatch? b = _monthFirst.firstMatch(title);
  if (b != null) {
    final int? m = _month(b.group(1)!);
    if (m != null) {
      return _valid(int.parse(b.group(3)!), m, int.parse(b.group(2)!));
    }
  }
  final RegExpMatch? c = _iso.firstMatch(title);
  if (c != null) {
    return _valid(int.parse(c.group(1)!), int.parse(c.group(2)!), int.parse(c.group(3)!));
  }
  return null;
}

DateTime? _valid(int y, int m, int d) {
  final DateTime t = DateTime(y, m, d);
  return t.month == m && t.day == d ? t : null;
}

/// Whole calendar days from the day of [nowMs] to [date]. Negative: passed.
int daysLeft(DateTime date, int nowMs) {
  final DateTime n = DateTime.fromMillisecondsSinceEpoch(nowMs);
  return DateTime.utc(date.year, date.month, date.day).difference(DateTime.utc(n.year, n.month, n.day)).inDays;
}

String daysLeftText(int n) {
  if (n == 0) {
    return 'Today';
  }
  if (n < 0) {
    return 'Date passed';
  }
  return n == 1 ? '1 day left' : '$n days left';
}

/// Share of the time from [createdAt] to [date] that has gone, 0..1.
double elapsedFraction(int createdAt, DateTime date, int nowMs) {
  final int span = date.millisecondsSinceEpoch - createdAt;
  if (span <= 0) {
    return 1;
  }
  return ((nowMs - createdAt) / span).clamp(0.0, 1.0).toDouble();
}

/// Sessions finished at or after [from].
int sessionsSince(List<Session> sessions, int from) {
  int n = 0;
  for (final Session s in sessions) {
    final int? e = s.endedAt;
    if (e != null && e >= from) {
      n++;
    }
  }
  return n;
}

/// Active goals that carry a date, nearest date first.
List<(Goal, DateTime)> datedGoals(List<Goal> goals) {
  final List<(Goal, DateTime)> out = <(Goal, DateTime)>[];
  for (final Goal g in goals) {
    final DateTime? d = g.done ? null : goalDate(g.title);
    if (d != null) {
      out.add((g, d));
    }
  }
  out.sort(((Goal, DateTime) a, (Goal, DateTime) b) => a.$2.compareTo(b.$2));
  return out;
}

/// The weekly target of the first active consistency goal, or null.
int? weeklyTarget(List<Goal> goals) {
  for (final Goal g in goals) {
    final int? n = g.sessionsPerWeek;
    if (!g.done && g.kind == 'consistency' && n != null && n > 0) {
      return n;
    }
  }
  return null;
}

/// One flag per calendar day, oldest first, ending today: a session ended.
List<bool> activeDays(List<Session> sessions, int count, int nowMs) {
  final DateTime n = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final DateTime today = DateTime(n.year, n.month, n.day);
  final Set<String> keys = <String>{};
  for (final Session s in sessions) {
    final int? e = s.endedAt;
    if (e != null) {
      final DateTime d = DateTime.fromMillisecondsSinceEpoch(e);
      keys.add('${d.year}-${d.month}-${d.day}');
    }
  }
  return <bool>[
    for (int i = count - 1; i >= 0; i--)
      keys.contains(_key(DateTime(today.year, today.month, today.day - i))),
  ];
}

String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// First letters of the weekdays of the last [count] days, oldest first.
List<String> dayLetters(int count, int nowMs) {
  const List<String> l = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  final DateTime n = DateTime.fromMillisecondsSinceEpoch(nowMs);
  return <String>[
    for (int i = count - 1; i >= 0; i--) l[DateTime(n.year, n.month, n.day - i).weekday - 1],
  ];
}

/// The newest finished session, or null.
Session? lastSession(List<Session> sessions) {
  Session? best;
  for (final Session s in sessions) {
    final int? e = s.endedAt;
    if (e != null && (best == null || e > best.endedAt!)) {
      best = s;
    }
  }
  return best;
}

/// "Gym, Legs".
String sessionName(Session s) {
  final String? f = s.focus;
  return f == null || f.isEmpty ? s.type : '${s.type}, $f';
}

/// "Last: yesterday, Gym, Legs".
String lastLine(Session s, int nowMs) {
  return 'Last: ${whenLabel(s.endedAt ?? s.startedAt, nowMs: nowMs).toLowerCase()}, ${sessionName(s)}';
}

double _top(Exercise e) {
  double t = 0;
  for (final SetEntry x in e.sets) {
    if (!x.isTime && x.kg > t) {
      t = x.kg;
    }
  }
  return t;
}

/// Exercises whose top set changed in the last [days] days, biggest change
/// first, at most [limit]. The start value is the top set of the last session
/// before the period when there is one, else the first one inside it. With
/// one session and nothing before it, nothing changed.
List<MovedRow> whatMoved(List<Session> sessions, int days, int nowMs, {int limit = 5}) {
  final List<Session> done = <Session>[
    for (final Session s in sessions)
      if (s.endedAt != null) s,
  ]..sort((Session a, Session b) => a.endedAt!.compareTo(b.endedAt!));
  final int from = nowMs - days * dayMs;
  final Map<String, double> before = <String, double>{};
  final Map<String, List<double>> inside = <String, List<double>>{};
  final Map<String, String> names = <String, String>{};
  for (final Session s in done) {
    for (final Exercise e in s.exercises) {
      final double t = _top(e);
      if (e.isTime || t <= 0) {
        continue;
      }
      final String k = e.name.trim().toLowerCase();
      names[k] = e.name;
      if (s.endedAt! >= from) {
        inside.putIfAbsent(k, () => <double>[]).add(t);
      } else {
        before[k] = t;
      }
    }
  }
  final List<(String, double, double)> moved = <(String, double, double)>[];
  for (final MapEntry<String, List<double>> en in inside.entries) {
    final double start = before[en.key] ?? en.value.first;
    final double end = en.value.last;
    if ((end - start).abs() >= 0.05) {
      moved.add((names[en.key]!, start, end));
    }
  }
  moved.sort(((String, double, double) a, (String, double, double) b) => (b.$3 - b.$2).abs().compareTo((a.$3 - a.$2).abs()));
  return <MovedRow>[
    for (final (String, double, double) m in moved.take(limit))
      MovedRow(name: m.$1, from: fmtKg(m.$2), to: fmtKg(m.$3), unit: 'kg', up: m.$3 > m.$2),
  ];
}

/// Dashboard modules the new blocks do not cover, kept in server order. The
/// sessions and active-days tiles, the consistency squares, the consistency
/// goal bar, goal bars with nothing to show, goal bars of dated goals and
/// trends of fewer than four points are dropped. The server recent list goes
/// too: the app draws its own.
Dashboard homeExtras(Dashboard d, List<Goal> goals) {
  final Set<String> dated = <String>{for (final (Goal, DateTime) g in datedGoals(goals)) g.$1.id};
  final Set<String> consistency = <String>{
    for (final Goal g in goals)
      if (g.kind == 'consistency') g.id,
  };
  final List<DashboardModule> keep = <DashboardModule>[];
  for (final DashboardModule m in d.modules) {
    switch (m.type) {
      case 'stat':
        final String l = m.label.toLowerCase();
        if (l.startsWith('sessions') || l.startsWith('active days')) {
          continue;
        }
      case 'consistency' || 'recent_sessions':
        continue;
      case 'goal_progress':
        if (m.fraction == null || dated.contains(m.goalId) || consistency.contains(m.goalId)) {
          continue;
        }
      case 'trend':
        if (m.points.length < 4) {
          continue;
        }
    }
    keep.add(m);
  }
  return Dashboard(days: d.days, source: d.source, modules: keep);
}
