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
  });

  final String id;
  final String threadId;

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
