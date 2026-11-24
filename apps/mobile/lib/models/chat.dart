import 'json_util.dart';

/// What a thread is about: today only a program. Without [id] it is a new
/// program that is still being talked through.
class ThreadAbout {
  const ThreadAbout({this.kind = 'program', this.id});

  final String kind;
  final String? id;

  bool get isProgram => kind == 'program';

  Map<String, dynamic> toJson() => <String, dynamic>{'kind': kind, if (id != null) 'id': id};

  static ThreadAbout? fromJson(Object? v) {
    if (v is! Map) {
      return null;
    }
    return ThreadAbout(kind: str(v['kind'], 'program'), id: strOrNull(v['id']));
  }
}

class Thread {
  const Thread({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.summary = '',
    this.lastMessage,
    this.status = 'idle',
    this.error,
    this.pending = 0,
    this.titleSource = 'user',
    this.placeId,
    this.about,
  });

  final String id;
  final String title;

  /// What this thread is about (a program), or null for an ordinary chat.
  final ThreadAbout? about;

  /// The place this thread is about, or null.
  final String? placeId;

  /// auto | user. `auto`: the title was made by the backend from the first
  /// message. `user`: the user named it. A row without it counts as `user`.
  final String titleSource;
  final int createdAt;
  final int updatedAt;
  final String summary;
  final String? lastMessage;

  /// idle | thinking | failed. `thinking` while a coach reply is running.
  final String status;

  /// Short reason when [status] is `failed`.
  final String? error;

  /// Coach replies still running.
  final int pending;

  bool get thinking => status == 'thinking';
  bool get failed => status == 'failed';

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> m = <String, dynamic>{
      'id': id,
      'title': title,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'summary': summary,
      'status': status,
      'pending': pending,
      'titleSource': titleSource,
    };
    if (placeId != null) {
      m['placeId'] = placeId;
    }
    if (about != null) {
      m['about'] = about!.toJson();
    }
    if (lastMessage != null) {
      m['lastMessage'] = lastMessage;
    }
    if (error != null) {
      m['error'] = error;
    }
    return m;
  }

  factory Thread.fromJson(Map<String, dynamic> j) {
    return Thread(
      id: str(j['id']),
      title: str(j['title']),
      createdAt: intOf(j['createdAt']),
      updatedAt: intOf(j['updatedAt']),
      summary: str(j['summary']),
      lastMessage: strOrNull(j['lastMessage']),
      status: str(j['status'], 'idle'),
      error: strOrNull(j['error']),
      pending: intOf(j['pending']),
      titleSource: str(j['titleSource'], 'user'),
      placeId: strOrNull(j['placeId']),
      about: ThreadAbout.fromJson(j['about']),
    );
  }
}

/// What was open when a message was sent (ADR-032). A hint for the coach: the
/// server reads the real data itself.
class ChatContext {
  const ChatContext({
    this.screen = 'chat',
    this.openSessionId,
    this.exerciseId,
    this.placeId,
    this.entryId,
    this.programId,
  });

  /// chat | log | session | exercise | program | start
  final String screen;
  final String? openSessionId;
  final String? exerciseId;
  final String? placeId;
  final String? entryId;
  final String? programId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'screen': screen,
        if (openSessionId != null) 'openSessionId': openSessionId,
        if (exerciseId != null) 'exerciseId': exerciseId,
        if (placeId != null) 'placeId': placeId,
        if (entryId != null) 'entryId': entryId,
        if (programId != null) 'programId': programId,
      };

  static ChatContext? fromJson(Object? v) {
    if (v is! Map) {
      return null;
    }
    return ChatContext(
      screen: str(v['screen'], 'chat'),
      openSessionId: strOrNull(v['openSessionId']),
      exerciseId: strOrNull(v['exerciseId']),
      placeId: strOrNull(v['placeId']),
      entryId: strOrNull(v['entryId']),
      programId: strOrNull(v['programId']),
    );
  }
}

/// What one function of a coach turn did: applied | drafted | rejected.
class CoachAction {
  const CoachAction({required this.actionId, required this.name, required this.status, this.reason});

  final String actionId;
  final String name;
  final String status;
  final String? reason;

  static CoachAction? fromJson(Object? v) {
    if (v is! Map) {
      return null;
    }
    return CoachAction(
      actionId: str(v['actionId']),
      name: str(v['name']),
      status: str(v['status'], 'rejected'),
      reason: strOrNull(v['reason']),
    );
  }
}

/// A question of the coach, with optional quick answers.
class CoachQuestion {
  const CoachQuestion({required this.text, this.answers = const <QuickAnswer>[]});

  final String text;
  final List<QuickAnswer> answers;

  static CoachQuestion? fromJson(Object? v) {
    if (v is! Map) {
      return null;
    }
    final Object? raw = v['answers'];
    return CoachQuestion(
      text: str(v['text']),
      answers: <QuickAnswer>[
        if (raw is List)
          for (final Object? a in raw)
            if (a is Map) QuickAnswer(id: str(a['id']), label: str(a['label'])),
      ],
    );
  }
}

/// A whole-workout proposal the coach shows above its buttons (optional).
class CoachPlan {
  const CoachPlan({this.title, this.rows = const <(String, String)>[]});

  final String? title;

  /// (exercise name, short sets text)
  final List<(String, String)> rows;

  static CoachPlan? fromJson(Object? v) {
    if (v is! Map) {
      return null;
    }
    final Object? raw = v['exercises'];
    return CoachPlan(
      title: strOrNull(v['title']),
      rows: <(String, String)>[
        if (raw is List)
          for (final Object? e in raw)
            if (e is Map) (str(e['name']), str(e['sets'])),
      ],
    );
  }
}

/// A tap on a quick answer, sent with the message.
class ChatAnswer {
  const ChatAnswer({required this.turnId, required this.id});

  final String turnId;
  final String id;

  Map<String, dynamic> toJson() => <String, dynamic>{'turnId': turnId, 'id': id};
}

class QuickAnswer {
  const QuickAnswer({required this.id, required this.label});

  final String id;
  final String label;
}

class Message {
  const Message({
    required this.id,
    required this.threadId,
    required this.role,
    required this.text,
    required this.createdAt,
    this.fileIds = const <String>[],
    this.sources = const <String>[],
    this.voice,
    this.proposalId,
    this.context,
    this.actions = const <CoachAction>[],
    this.question,
    this.proposal,
    this.turnId,
  });

  final String id;
  final String threadId;

  /// The user message a coach turn answers (assistant messages).
  final String? turnId;

  /// A whole-workout proposal shown above the question buttons, when present.
  final CoachPlan? proposal;

  /// What was open when the person sent it (user messages).
  final ChatContext? context;

  /// What the functions of a coach turn did (assistant messages).
  final List<CoachAction> actions;
  final CoachQuestion? question;

  /// user | assistant
  final String role;
  final String text;
  final List<String> fileIds;

  /// What the coach also read, e.g. "Knee thread", "gym log", "goals".
  final List<String> sources;
  final int createdAt;

  /// Set on a voice message: pending | done | failed. Null on a text message.
  final String? voice;

  /// The proposal the coach made with this message (assistant messages only).
  final String? proposalId;

  bool get mine => role == 'user';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'threadId': threadId,
      'role': role,
      'text': text,
      'fileIds': fileIds,
      'sources': sources,
      'createdAt': createdAt,
      if (voice != null) 'voice': voice,
      if (proposalId != null) 'proposalId': proposalId,
    };
  }

  factory Message.fromJson(Map<String, dynamic> j) {
    return Message(
      id: str(j['id']),
      threadId: str(j['threadId']),
      role: str(j['role'], 'assistant'),
      text: str(j['text']),
      createdAt: intOf(j['createdAt']),
      fileIds: strList(j['fileIds']),
      sources: strList(j['sources']),
      voice: strOrNull(j['voice']),
      proposalId: strOrNull(j['proposalId']),
      context: ChatContext.fromJson(j['context']),
      actions: <CoachAction>[
        if (j['actions'] is List)
          for (final Object? a in j['actions'] as List)
            if (CoachAction.fromJson(a) case final CoachAction x) x,
      ],
      question: CoachQuestion.fromJson(j['question']),
      proposal: CoachPlan.fromJson(j['proposal']),
      turnId: strOrNull(j['turnId']),
    );
  }
}

class FileMeta {
  const FileMeta({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    required this.kind,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String mime;
  final int size;

  /// text | image | pdf | audio | other
  final String kind;
  final int createdAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'mime': mime,
      'size': size,
      'kind': kind,
      'createdAt': createdAt,
    };
  }

  factory FileMeta.fromJson(Map<String, dynamic> j) {
    return FileMeta(
      id: str(j['id']),
      name: str(j['name']),
      mime: str(j['mime']),
      size: intOf(j['size']),
      kind: str(j['kind'], 'other'),
      createdAt: intOf(j['createdAt']),
    );
  }
}
