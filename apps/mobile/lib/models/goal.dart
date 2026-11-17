import 'json_util.dart';

const List<String> goalKinds = <String>[
  'strength',
  'consistency',
  'work_around',
  'custom',
];

class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.kind,
    required this.status,
    required this.source,
    required this.createdAt,
    this.exercise,
    this.targetKg,
    this.sessionsPerWeek,
    this.threadId,
    this.importId,
  });

  final String id;
  final String title;

  /// strength | consistency | work_around | custom
  final String kind;
  final String? exercise;
  final double? targetKg;
  final int? sessionsPerWeek;

  /// active | done
  final String status;

  /// user | ai | import
  final String source;
  final String? threadId;
  final String? importId;
  final int createdAt;

  bool get done => status == 'done';

  Goal copyWith({
    String? title,
    String? kind,
    String? exercise,
    double? targetKg,
    int? sessionsPerWeek,
    String? status,
  }) {
    return Goal(
      id: id,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      source: source,
      createdAt: createdAt,
      exercise: exercise ?? this.exercise,
      targetKg: targetKg ?? this.targetKg,
      sessionsPerWeek: sessionsPerWeek ?? this.sessionsPerWeek,
      threadId: threadId,
      importId: importId,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> m = <String, dynamic>{
      'id': id,
      'title': title,
      'kind': kind,
      'status': status,
      'source': source,
      'createdAt': createdAt,
    };
    if (exercise != null) {
      m['exercise'] = exercise;
    }
    if (targetKg != null) {
      m['targetKg'] = targetKg;
    }
    if (sessionsPerWeek != null) {
      m['sessionsPerWeek'] = sessionsPerWeek;
    }
    if (threadId != null) {
      m['threadId'] = threadId;
    }
    if (importId != null) {
      m['importId'] = importId;
    }
    return m;
  }

  factory Goal.fromJson(Map<String, dynamic> j) {
    return Goal(
      id: str(j['id']),
      title: str(j['title']),
      kind: str(j['kind'], 'custom'),
      status: str(j['status'], 'active'),
      source: str(j['source'], 'user'),
      createdAt: intOf(j['createdAt']),
      exercise: strOrNull(j['exercise']),
      targetKg: dblOrNull(j['targetKg']),
      sessionsPerWeek: intOrNull(j['sessionsPerWeek']),
      threadId: strOrNull(j['threadId']),
      importId: strOrNull(j['importId']),
    );
  }
}

class ContextItem {
  const ContextItem({
    required this.id,
    required this.text,
    required this.topic,
    required this.active,
    required this.source,
    required this.createdAt,
    this.threadId,
    this.importId,
  });

  final String id;
  final String text;
  final String topic;
  final bool active;

  /// user | ai | import
  final String source;
  final String? threadId;
  final String? importId;
  final int createdAt;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> m = <String, dynamic>{
      'id': id,
      'text': text,
      'topic': topic,
      'active': active,
      'source': source,
      'createdAt': createdAt,
    };
    if (threadId != null) {
      m['threadId'] = threadId;
    }
    if (importId != null) {
      m['importId'] = importId;
    }
    return m;
  }

  factory ContextItem.fromJson(Map<String, dynamic> j) {
    return ContextItem(
      id: str(j['id']),
      text: str(j['text']),
      topic: str(j['topic']),
      active: j['active'] != false,
      source: str(j['source'], 'user'),
      createdAt: intOf(j['createdAt']),
      threadId: strOrNull(j['threadId']),
      importId: strOrNull(j['importId']),
    );
  }
}

/// A change to a goal. Only the fields that are set are sent and applied.
class GoalPatch {
  const GoalPatch({
    this.title,
    this.kind,
    this.exercise,
    this.targetKg,
    this.sessionsPerWeek,
    this.status,
  });

  final String? title;
  final String? kind;
  final String? exercise;
  final double? targetKg;
  final int? sessionsPerWeek;
  final String? status;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (title != null) 'title': title,
      if (kind != null) 'kind': kind,
      if (exercise != null) 'exercise': exercise,
      if (targetKg != null) 'targetKg': targetKg,
      if (sessionsPerWeek != null) 'sessionsPerWeek': sessionsPerWeek,
      if (status != null) 'status': status,
    };
  }

  factory GoalPatch.fromJson(Map<String, dynamic> j) {
    return GoalPatch(
      title: strOrNull(j['title']),
      kind: strOrNull(j['kind']),
      exercise: strOrNull(j['exercise']),
      targetKg: dblOrNull(j['targetKg']),
      sessionsPerWeek: intOrNull(j['sessionsPerWeek']),
      status: strOrNull(j['status']),
    );
  }

  Goal applyTo(Goal g) {
    return g.copyWith(
      title: title,
      kind: kind,
      exercise: exercise,
      targetKg: targetKg,
      sessionsPerWeek: sessionsPerWeek,
      status: status,
    );
  }
}

/// A change to a context note: switch it on or off, or change its text.
class ContextPatch {
  const ContextPatch({this.text, this.active});

  final String? text;
  final bool? active;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (text != null) 'text': text,
      if (active != null) 'active': active,
    };
  }

  factory ContextPatch.fromJson(Map<String, dynamic> j) {
    return ContextPatch(
      text: strOrNull(j['text']),
      active: j['active'] is bool ? j['active'] as bool : null,
    );
  }

  ContextItem applyTo(ContextItem c) {
    return ContextItem(
      id: c.id,
      text: text ?? c.text,
      topic: c.topic,
      active: active ?? c.active,
      source: c.source,
      createdAt: c.createdAt,
      threadId: c.threadId,
      importId: c.importId,
    );
  }
}
