import 'goal.dart';
import 'json_util.dart';

class Thread {
  const Thread({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.summary = '',
    this.lastMessage,
  });

  final String id;
  final String title;
  final int createdAt;
  final int updatedAt;
  final String summary;
  final String? lastMessage;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> m = <String, dynamic>{
      'id': id,
      'title': title,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'summary': summary,
    };
    if (lastMessage != null) {
      m['lastMessage'] = lastMessage;
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

/// Reply to POST /v1/threads/:id/messages.
class SendResult {
  const SendResult({
    required this.userMessage,
    required this.assistantMessage,
    this.goals = const <Goal>[],
    this.context = const <ContextItem>[],
  });

  final Message userMessage;
  final Message assistantMessage;
  final List<Goal> goals;
  final List<ContextItem> context;

  factory SendResult.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> x = asMap(j['extracted']);
    return SendResult(
      userMessage: Message.fromJson(asMap(j['userMessage'])),
      assistantMessage: Message.fromJson(asMap(j['assistantMessage'])),
      goals: asList(x['goals'])
          .map((Object? e) => Goal.fromJson(asMap(e)))
          .toList(),
      context: asList(x['context'])
          .map((Object? e) => ContextItem.fromJson(asMap(e)))
          .toList(),
    );
  }
}
