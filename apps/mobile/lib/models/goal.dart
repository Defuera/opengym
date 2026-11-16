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
