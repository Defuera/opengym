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
    this.goal,
    this.limit,
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

  /// One plain line each, made from the parts the server sent.
  final String? goal;
  final String? limit;
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
      goal: _goalLine(v['goal']),
      limit: _limitLine(v['limit']),
      note: v['note'] is Map ? strOrNull((v['note'] as Map)['text']) : null,
      changes: v['edits'] is Map && (v['edits'] as Map).isNotEmpty,
      noEntry: v['noEntry'] == true,
      state: const <String>['open', 'applied', 'stale'].contains(v['state']) ? v['state'] as String : 'open',
      entryId: strOrNull(v['entryId']),
    );
  }
}

String _num(num n) => n == n.truncate() ? n.toInt().toString() : n.toString();

String? _goalLine(Object? v) {
  if (v is! Map) {
    return null;
  }
  final List<String> parts = <String>[
    str(v['title']),
    if (v['targetKg'] is num) '${_num(v['targetKg'] as num)} kg',
    if (v['sessionsPerWeek'] is num) '${_num(v['sessionsPerWeek'] as num)} a week',
  ].where((String s) => s.isNotEmpty).toList();
  return parts.isEmpty ? null : parts.join(', ');
}

String? _limitLine(Object? v) {
  if (v is! Map) {
    return null;
  }
  final String key = str(v['part']);
  final String part = key.isEmpty ? '' : partLabel(key);
  final String title = str(v['title']);
  final String head = part.isEmpty ? title : (title.isEmpty || title == part ? part : '$part: $title');
  final List<String> rules = <String>[
    for (final Object? r in asList(v['rules']))
      if (r is Map && str(r['text']).isNotEmpty) '${str(r['kind'])} ${str(r['text'])}'.trim(),
  ];
  final String all = rules.isEmpty ? head : '$head (${rules.join('; ')})';
  return all.isEmpty ? null : all;
}
