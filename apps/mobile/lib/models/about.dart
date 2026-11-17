/// "About me": limits with rules, records and check-ins, and the body load.
/// Pure Dart. Wire shapes follow the Convex contract (`limitId`, `recordId`,
/// `checkinId`); the models call them `id`.
library;

import 'about_parts.dart';
import 'json_util.dart';

/// One rule of a limit: [kind] is avoid | light | do.
class LimitRule {
  const LimitRule({required this.kind, required this.text, this.exercises = const <String>[]});

  final String kind;
  final String text;
  final List<String> exercises;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind,
        'text': text,
        if (exercises.isNotEmpty) 'exercises': exercises,
      };

  factory LimitRule.fromJson(Object? v) {
    final Map<String, dynamic> j = asMap(v);
    return LimitRule(
      kind: str(j['kind'], 'avoid'),
      text: str(j['text']),
      exercises: strList(j['exercises']),
    );
  }
}

/// The user's own text (a scan report, say), kept word for word.
class LimitRecord {
  const LimitRecord({
    required this.id,
    required this.limitId,
    required this.title,
    required this.text,
    this.date,
  });

  final String id;
  final String limitId;
  final String title;

  /// YYYY-MM-DD, if the user gave one.
  final String? date;
  final String text;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'recordId': id,
        'limitId': limitId,
        'title': title,
        if (date != null) 'date': date,
        'text': text,
      };

  factory LimitRecord.fromJson(Object? v, {String limitId = ''}) {
    final Map<String, dynamic> j = asMap(v);
    return LimitRecord(
      id: str(j['recordId'], str(j['id'])),
      limitId: str(j['limitId'], limitId),
      title: str(j['title']),
      date: strOrNull(j['date']),
      text: str(j['text']),
    );
  }
}

/// The user's answer to "How was the <part> today?": fine | noticed | bad.
class Checkin {
  const Checkin({
    required this.id,
    required this.limitId,
    required this.at,
    required this.feeling,
    this.sessionId,
    this.sessionLabel,
  });

  final String id;
  final String limitId;
  final int at;
  final String feeling;
  final String? sessionId;

  /// Server-made, e.g. "Gym, Upper". Read only.
  final String? sessionLabel;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'checkinId': id,
        'limitId': limitId,
        if (sessionId != null) 'sessionId': sessionId,
        'at': at,
        'feeling': feeling,
      };

  factory Checkin.fromJson(Object? v, {String limitId = ''}) {
    final Map<String, dynamic> j = asMap(v);
    return Checkin(
      id: str(j['checkinId'], str(j['id'])),
      limitId: str(j['limitId'], limitId),
      at: intOf(j['at']),
      feeling: str(j['feeling'], 'fine'),
      sessionId: strOrNull(j['sessionId']),
      sessionLabel: strOrNull(j['sessionLabel']),
    );
  }
}

/// A body part the user trains around. [status] is active | improving | cleared.
class Limit {
  const Limit({
    required this.id,
    required this.part,
    required this.title,
    required this.status,
    this.since,
    this.rules = const <LimitRule>[],
    this.records = const <LimitRecord>[],
    this.checkins = const <Checkin>[],
  });

  final String id;
  final String part;
  final String title;
  final String status;

  /// YYYY-MM
  final String? since;
  final List<LimitRule> rules;
  final List<LimitRecord> records;

  /// Newest first.
  final List<Checkin> checkins;

  bool get cleared => status == 'cleared';

  Limit copyWith({
    String? title,
    String? status,
    List<LimitRule>? rules,
    List<LimitRecord>? records,
    List<Checkin>? checkins,
  }) =>
      Limit(
        id: id,
        part: part,
        title: title ?? this.title,
        status: status ?? this.status,
        since: since,
        rules: rules ?? this.rules,
        records: records ?? this.records,
        checkins: checkins ?? this.checkins,
      );

  /// The `Limit` of the save command. Records and check-ins have own commands.
  Map<String, dynamic> toWire() => <String, dynamic>{
        'limitId': id,
        'part': part,
        'title': title,
        'status': status,
        if (since != null) 'since': since,
        'rules': <Map<String, dynamic>>[for (final LimitRule r in rules) r.toJson()],
      };

  factory Limit.fromJson(Object? v) {
    final Map<String, dynamic> j = asMap(v);
    final String id = str(j['limitId'], str(j['id']));
    return Limit(
      id: id,
      part: str(j['part']),
      title: str(j['title']),
      status: str(j['status'], 'active'),
      since: strOrNull(j['since']),
      rules: <LimitRule>[for (final Object? r in asList(j['rules'])) LimitRule.fromJson(r)],
      records: <LimitRecord>[
        for (final Object? r in asList(j['records'])) LimitRecord.fromJson(r, limitId: id),
      ],
      checkins: <Checkin>[
        for (final Object? c in asList(j['checkins'])) Checkin.fromJson(c, limitId: id),
      ],
    );
  }
}

/// The answer of `queries/aboutMe:get`.
class AboutMe {
  const AboutMe({
    this.limits = const <Limit>[],
    this.load14 = const <String, int>{},
    this.load90 = const <String, int>{},
    this.focusParts = const <String>[],
  });

  final List<Limit> limits;

  /// Muscle key -> level 0..3.
  final Map<String, int> load14;
  final Map<String, int> load90;
  final List<String> focusParts;

  /// The load of the last [days] days: 14 or 90.
  Map<String, int> loadFor(int days) => days == 14 ? load14 : load90;

  Limit? limitById(String id) {
    for (final Limit l in limits) {
      if (l.id == id) {
        return l;
      }
    }
    return null;
  }

  /// The limit that covers a tapped [key], active ones first.
  Limit? limitForPart(String key) {
    Limit? found;
    for (final Limit l in limits) {
      if (!partCovers(l.part, key)) {
        continue;
      }
      if (!l.cleared) {
        return l;
      }
      found ??= l;
    }
    return found;
  }

  AboutMe copyWith({List<Limit>? limits}) => AboutMe(
        limits: limits ?? this.limits,
        load14: load14,
        load90: load90,
        focusParts: focusParts,
      );

  factory AboutMe.fromJson(Object? v) {
    final Map<String, dynamic> j = asMap(v);
    final Map<String, dynamic> load = asMap(j['load']);
    Map<String, int> levels(Object? m) => <String, int>{
          for (final MapEntry<String, dynamic> e in asMap(m).entries)
            e.key: intOf(e.value).clamp(0, 3),
        };
    return AboutMe(
      limits: <Limit>[for (final Object? l in asList(j['limits'])) Limit.fromJson(l)],
      load14: levels(load['d14']),
      load90: levels(load['d90']),
      focusParts: strList(j['focusParts']),
    );
  }
}

/// A limit that a just-finished session loaded, with no check-in yet.
class AskItem {
  const AskItem({required this.limitId, required this.title, required this.part});

  final String limitId;
  final String title;
  final String part;

  factory AskItem.fromJson(Object? v) {
    final Map<String, dynamic> j = asMap(v);
    return AskItem(
      limitId: str(j['limitId']),
      title: str(j['title']),
      part: str(j['part']),
    );
  }
}
