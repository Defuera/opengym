import 'json_util.dart';

/// A start suggestion from GET /v1/start (or from the local planner).
class Prediction {
  const Prediction({required this.kind, required this.type, this.reason = ''});

  /// gym | activity
  final String kind;
  final String type;
  final String reason;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'kind': kind, 'type': type, 'reason': reason};
  }

  factory Prediction.fromJson(Map<String, dynamic> j) {
    return Prediction(
      kind: str(j['kind'], 'gym') == 'activity' ? 'activity' : 'gym',
      type: str(j['type']),
      reason: str(j['reason']),
    );
  }
}

class ImportCounts {
  const ImportCounts({this.sessions = 0, this.goals = 0, this.context = 0});

  final int sessions;
  final int goals;
  final int context;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sessions': sessions,
      'goals': goals,
      'context': context,
    };
  }

  factory ImportCounts.fromJson(Map<String, dynamic> j) {
    return ImportCounts(
      sessions: intOf(j['sessions']),
      goals: intOf(j['goals']),
      context: intOf(j['context']),
    );
  }
}

class ImportJob {
  const ImportJob({
    required this.id,
    required this.status,
    required this.total,
    required this.processed,
    required this.counts,
    required this.notes,
    required this.createdAt,
  });

  final String id;

  /// running | done | failed
  final String status;
  final int total;
  final int processed;
  final ImportCounts counts;
  final List<String> notes;
  final int createdAt;

  bool get running => status == 'running';
  bool get failed => status == 'failed';
  bool get finished => status == 'done' || status == 'failed';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'status': status,
      'total': total,
      'processed': processed,
      'counts': counts.toJson(),
      'notes': notes,
      'createdAt': createdAt,
    };
  }

  factory ImportJob.fromJson(Map<String, dynamic> j) {
    return ImportJob(
      id: str(j['id']),
      status: str(j['status'], 'running'),
      total: intOf(j['total']),
      processed: intOf(j['processed']),
      counts: ImportCounts.fromJson(asMap(j['counts'])),
      notes: strList(j['notes']),
      createdAt: intOf(j['createdAt']),
    );
  }
}

class Review {
  const Review({
    required this.sessionId,
    required this.source,
    required this.summary,
    this.changes = const <String>[],
  });

  final String sessionId;

  /// ai | rules
  final String source;
  final String summary;
  final List<String> changes;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sessionId': sessionId,
      'source': source,
      'summary': summary,
      'changes': changes,
    };
  }

  factory Review.fromJson(Map<String, dynamic> j) {
    return Review(
      sessionId: str(j['sessionId']),
      source: str(j['source'], 'rules'),
      summary: str(j['summary']),
      changes: strList(j['changes']),
    );
  }
}

/// Reply to GET /v1/health.
class HealthInfo {
  const HealthInfo({
    required this.ok,
    required this.provider,
    required this.aiConfigured,
    required this.version,
  });

  final bool ok;
  final String provider;
  final bool aiConfigured;
  final String version;

  factory HealthInfo.fromJson(Map<String, dynamic> j) {
    return HealthInfo(
      ok: j['ok'] == true,
      provider: str(j['provider']),
      aiConfigured: j['aiConfigured'] == true,
      version: str(j['version']),
    );
  }
}
