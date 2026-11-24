import '../entry_category.dart';
import 'about_parts.dart';
import 'json_util.dart';

/// The session part of a log draft (ADR-032): the activity, time, distance and
/// exercises with a short sets text ("3 x 10").
class LogDraftSession {
  const LogDraftSession({
    required this.type,
    this.focus,
    this.minutes,
    this.distanceKm,
    this.exercises = const <(String, String)>[],
  });

  final String type;
  final String? focus;
  final int? minutes;
  final double? distanceKm;

  /// (exercise name, short sets text)
  final List<(String, String)> exercises;

  static LogDraftSession? fromJson(Object? v) {
    if (v is! Map) {
      return null;
    }
    final Object? raw = v['exercises'];
    return LogDraftSession(
      type: str(v['type']),
      focus: strOrNull(v['focus']),
      minutes: intOrNull(v['minutes']),
      distanceKm: dblOrNull(v['distanceKm']),
      exercises: <(String, String)>[
        if (raw is List)
          for (final Object? e in raw)
            if (e is Map) (str(e['name']), str(e['sets'])),
      ],
    );
  }
}

/// A log the coach drafted in the log chat. Nothing is written until the
/// person presses Done. [state] is open | applied | stale.
class LogDraft {
  const LogDraft({
    required this.kind,
    this.color,
    required this.summary,
    required this.at,
    this.session,
    this.goalRows = const <(String, String)>[],
    this.limitRows = const <(String, String)>[],
    this.note,
    this.changes = false,
    this.noEntry = false,
    this.state = 'open',
    this.entryId,
  });

  /// The category label (old: meal | training | body | goal | other).
  final String kind;

  /// The category colour, "#RRGGBB", from the server. Null: none.
  final String? color;
  final String summary;
  final int at;
  final LogDraftSession? session;

  /// The goal and the limit as separate labelled rows (Exercise, Target, Per
  /// week; Body part, Avoid, ...), made from the structure the server sent.
  /// Empty: the draft holds no such part. The title is a row only when it
  /// says more than the summary does.
  final List<(String, String)> goalRows;
  final List<(String, String)> limitRows;
  final String? note;

  /// A goal, limit or note draft that changes one the person has, not a new one.
  final bool changes;

  /// Made outside the log chat (ADR-032, step D): Done writes the parts only, no log entry.
  final bool noEntry;
  final String state;
  final String? entryId;

  bool get open => state == 'open';
  bool get applied => state == 'applied';
  bool get stale => state == 'stale';

  /// The category ("Meal", "Sleep", ...), or "Note" when there is none.
  String get kindLabel => noEntry ? '${changes ? 'Change' : 'New'} ${kind.toLowerCase()}' : (categoryLabel(kind) ?? 'Note');

  /// Reads `proposal` when its `type` is `log`; null for anything else.
  static LogDraft? fromJson(Object? v) {
    if (v is! Map || v['type'] != 'log') {
      return null;
    }
    return LogDraft(
      kind: str(v['kind'], 'other'),
      color: strOrNull(v['color']),
      summary: str(v['summary']),
      at: intOf(v['at']),
      session: LogDraftSession.fromJson(v['session']),
      goalRows: _goalRows(v['goal'], str(v['summary'])),
      limitRows: _limitRows(v['limit'], str(v['summary'])),
      note: v['note'] is Map ? strOrNull((v['note'] as Map)['text']) : null,
      changes: v['edits'] is Map && (v['edits'] as Map).isNotEmpty,
      noEntry: v['noEntry'] == true,
      state: const <String>['open', 'applied', 'stale'].contains(v['state']) ? v['state'] as String : 'open',
      entryId: strOrNull(v['entryId']),
    );
  }
}

String _num(num n) => n == n.truncate() ? n.toInt().toString() : n.toString();

List<(String, String)> _goalRows(Object? v, String summary) {
  if (v is! Map) {
    return const <(String, String)>[];
  }
  final String title = str(v['title']);
  return <(String, String)>[
    if (title.isNotEmpty && title != summary) ('Goal', title),
    if (str(v['exercise']).isNotEmpty) ('Exercise', str(v['exercise'])),
    if (v['targetKg'] is num) ('Target', '${_num(v['targetKg'] as num)} kg'),
    if (v['sessionsPerWeek'] is num) ('Per week', _num(v['sessionsPerWeek'] as num)),
  ];
}

List<(String, String)> _limitRows(Object? v, String summary) {
  if (v is! Map) {
    return const <(String, String)>[];
  }
  final String key = str(v['part']);
  final String title = str(v['title']);
  final String status = str(v['status']);
  return <(String, String)>[
    if (title.isNotEmpty && title != summary) ('Limit', title),
    if (key.isNotEmpty) ('Body part', partLabel(key)),
    if (status.isNotEmpty && status != 'active') ('Status', '${status[0].toUpperCase()}${status.substring(1)}'),
    for (final Object? r in asList(v['rules']))
      if (r is Map && str(r['text']).isNotEmpty) (_cap(str(r['kind'], 'do')), str(r['text'])),
  ];
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
