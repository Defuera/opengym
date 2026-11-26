import 'chat.dart' show CoachQuestion;
import 'json_util.dart';

/// A start suggestion (from the server or the local planner): one ACTIVITY
/// ([type], e.g. Gym or Run) and the advised [focus] of that session, if any.
class Prediction {
  const Prediction({
    required this.kind,
    required this.type,
    this.focus,
    this.reason = '',
  });

  /// gym | activity
  final String kind;

  /// The activity name (from the log). 'Gym' when the server sent none.
  final String type;

  /// The advised flavour ('Upper', or 'Easy' for a run). Advice only.
  final String? focus;
  final String reason;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'kind': kind,
      'type': type,
      if (focus != null) 'focus': focus,
      'reason': reason,
    };
  }

  /// Reads a prediction. A gym item without a name is the activity Gym.
  factory Prediction.fromJson(Map<String, dynamic> j) {
    final String kind = str(j['kind'], 'gym') == 'activity' ? 'activity' : 'gym';
    final String type = str(j['type']);
    final String? focus = strOrNull(j['focus']);
    return Prediction(
      kind: kind,
      type: (kind == 'gym' && type.isEmpty) ? 'Gym' : type,
      focus: (focus == null || focus.isEmpty) ? null : focus,
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

/// The coach's review of a finished session (ADR-041). A NEW one is a debrief:
/// a [message] in the coach's voice, a [question] with quick answers, and the
/// chat it opened ([debriefThreadId], [debriefAnswered]). An OLD one has only a
/// [summary] and [changes]; it still shows.
class Review {
  const Review({
    required this.sessionId,
    required this.source,
    this.summary = '',
    this.changes = const <String>[],
    this.message = '',
    this.question,
    this.debriefThreadId,
    this.debriefAnswered = false,
  });

  final String sessionId;

  /// ai | rules
  final String source;
  final String summary;
  final List<String> changes;

  /// The debrief text, or '' for an old review.
  final String message;
  final CoachQuestion? question;

  /// The debrief chat, when the person opened it; [debriefAnswered] when they replied in it.
  final String? debriefThreadId;
  final bool debriefAnswered;

  /// A new review: the coach's debrief with its question.
  bool get isDebrief => message.trim().isNotEmpty;

  /// One text for a short card: the debrief message, else the old summary.
  String get text => isDebrief ? message : summary;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sessionId': sessionId,
      'source': source,
      'summary': summary,
      'changes': changes,
      if (isDebrief) 'message': message,
    };
  }

  factory Review.fromJson(Map<String, dynamic> j, {Map<String, dynamic>? debrief}) {
    final CoachQuestion? q = CoachQuestion.fromJson(j['question']);
    return Review(
      sessionId: str(j['sessionId']),
      source: str(j['source'], 'rules'),
      summary: str(j['summary']),
      changes: strList(j['changes']),
      message: str(j['message']),
      question: (q == null || q.text.isEmpty) ? null : q,
      debriefThreadId: debrief == null ? null : strOrNull(debrief['threadId']),
      debriefAnswered: debrief != null && debrief['answered'] == true,
    );
  }
}
