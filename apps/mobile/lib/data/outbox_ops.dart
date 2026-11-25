import '../models.dart';
import '../models/json_util.dart';
import 'convex_client.dart';
import 'upload_item.dart';

/// One write waiting to be sent. Self-contained and JSON-safe, so it can sit
/// on disk across restarts. Every op maps to one idempotent Convex command.
class OutboxOp {
  const OutboxOp({
    required this.seq,
    required this.type,
    required this.args,
    this.attempts = 0,
    this.failures = 0,
    this.parked = false,
  });

  /// Order of arrival. Ops are sent in this order.
  final int seq;
  final String type;
  final Map<String, dynamic> args;
  final int attempts;

  /// Consecutive failed sends while the link was verified up. At the limit
  /// the write is parked so it cannot block the ones behind it.
  final int failures;

  /// Set aside after too many failures. Kept on disk; never sent until retried.
  final bool parked;

  static const String sessionSave = 'session.save';
  static const String sessionRemove = 'session.remove';
  static const String sessionLogText = 'session.logText';
  static const String sessionSetPlace = 'session.setPlace';
  static const String goalCreate = 'goal.create';
  static const String goalUpdate = 'goal.update';
  static const String goalRemove = 'goal.remove';
  static const String contextCreate = 'context.create';
  static const String contextUpdate = 'context.update';
  static const String contextRemove = 'context.remove';
  static const String limitSave = 'limit.save';
  static const String limitRemove = 'limit.remove';
  static const String recordAdd = 'record.add';
  static const String recordRemove = 'record.remove';
  static const String checkinSave = 'checkin.save';

  /// A chat message (ADR-037): creates the thread when `thread` is set, uploads
  /// the files, then sends the message. Every step is idempotent.
  static const String chatSend = 'chat.send';

  OutboxOp copyWith({int? attempts, int? failures, bool? parked}) => OutboxOp(
        seq: seq,
        type: type,
        args: args,
        attempts: attempts ?? this.attempts,
        failures: failures ?? this.failures,
        parked: parked ?? this.parked,
      );

  OutboxOp withAttempt({bool counted = false}) =>
      copyWith(attempts: attempts + 1, failures: counted ? failures + 1 : failures);

  /// The record this op changes (session, goal or note id).
  String get targetId => str(args['id']);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'seq': seq,
        'type': type,
        'args': args,
        'attempts': attempts,
        'failures': failures,
        'parked': parked,
      };

  static OutboxOp? tryParse(Object? v) {
    if (v is! Map) {
      return null;
    }
    final Map<String, dynamic> m = asMap(v);
    final String type = str(m['type']);
    if (type.isEmpty) {
      return null;
    }
    return OutboxOp(
      seq: intOf(m['seq']),
      type: type,
      args: asMap(m['args']),
      attempts: intOf(m['attempts']),
      failures: intOf(m['failures']),
      parked: m['parked'] == true,
    );
  }

  /// Send this op through the gateway.
  Future<void> send(ConvexClient c) {
    switch (type) {
      case sessionSave:
        return c.saveSession(Session.fromJson(asMap(args['session'])));
      case sessionRemove:
        return c.removeSession(targetId);
      case sessionSetPlace:
        return c.setSessionPlace(sessionId: targetId, placeId: strOrNull(args['placeId']));
      case sessionLogText:
        return c.logSessionText(
          sessionId: targetId,
          type: str(args['type']),
          text: str(args['text']),
          at: intOf(args['at']),
        );
      case goalCreate:
        return c.createGoal(
          goalId: targetId,
          title: str(args['title']),
          kind: str(args['kind'], 'custom'),
          exercise: strOrNull(args['exercise']),
          targetKg: dblOrNull(args['targetKg']),
          sessionsPerWeek: intOrNull(args['sessionsPerWeek']),
        );
      case goalUpdate:
        return c.updateGoal(targetId, GoalPatch.fromJson(asMap(args['patch'])));
      case goalRemove:
        return c.removeGoal(targetId);
      case contextCreate:
        return c.createContext(
          itemId: targetId,
          text: str(args['text']),
          topic: str(args['topic']),
        );
      case contextUpdate:
        return c.updateContext(targetId, ContextPatch.fromJson(asMap(args['patch'])));
      case contextRemove:
        return c.removeContext(targetId);
      case limitSave:
        return c.saveLimit(Limit.fromJson(args['limit']));
      case limitRemove:
        return c.removeLimit(targetId);
      case recordAdd:
        return c.addRecord(LimitRecord.fromJson(args['record']));
      case recordRemove:
        return c.removeRecord(targetId);
      case checkinSave:
        return c.saveCheckin(Checkin.fromJson(args['checkin']));
      case chatSend:
        return _sendChat(c);
    }
    // An op from a newer app version: drop it rather than block the queue.
    return Future<void>.error(
        const ConvexCallException('Unknown change.', kind: ConvexFailure.rejected));
  }
}

/// Files of chat messages that wait in the outbox. The op holds only the path
/// (it must survive a restart); this keeps the picked item in this run, so an
/// in-memory item is still readable and a file is not uploaded twice.
class ChatFiles {
  ChatFiles._();

  static final Map<String, UploadItem> items = <String, UploadItem>{};
  static final Set<String> uploaded = <String>{};
}

/// A queued chat message and what the screen needs to show it.
class QueuedChat {
  const QueuedChat({
    required this.messageId,
    required this.threadId,
    required this.text,
    required this.createdAt,
    required this.files,
    required this.fileIds,
    required this.newThread,
    this.threadTitle,
    this.threadAbout,
    this.context,
    this.answer,
  });

  final String messageId;
  final String threadId;
  final String text;
  final int createdAt;
  final List<UploadItem> files;
  final List<String> fileIds;
  final bool newThread;
  final String? threadTitle;
  final ThreadAbout? threadAbout;
  final ChatContext? context;
  final ChatAnswer? answer;
}

extension OutboxChat on OutboxOp {
  Future<void> _sendChat(ConvexClient c) async {
    final Object? thread = args['thread'];
    final String threadId = str(args['threadId']);
    if (thread is Map) {
      await c.createThread(
        threadId: threadId,
        title: strOrNull(thread['title']),
        placeId: strOrNull(thread['placeId']),
        about: ThreadAbout.fromJson(thread['about']),
      );
    }
    final List<String> fileIds = <String>[];
    for (final Object? f in (args['files'] as List<dynamic>? ?? const <dynamic>[])) {
      final Map<String, dynamic> m = asMap(f);
      final String id = str(m['id']);
      fileIds.add(id);
      if (!ChatFiles.uploaded.contains(id)) {
        final UploadItem item = ChatFiles.items[id] ?? UploadItem(path: str(m['path']), name: str(m['name']));
        await c.uploadFile(fileId: id, name: item.name, mime: item.mime, bytes: await item.read());
        ChatFiles.uploaded.add(id);
      }
    }
    final Object? answer = args['answer'];
    await c.sendMessage(
      threadId: threadId,
      messageId: targetId,
      text: str(args['text']),
      fileIds: fileIds,
      context: ChatContext.fromJson(args['context']),
      answer: answer is Map ? ChatAnswer(turnId: str(answer['turnId']), id: str(answer['id'])) : null,
    );
  }

  /// The chat message this op holds, for the screen. Null for another type.
  QueuedChat? get chat {
    if (type != OutboxOp.chatSend) {
      return null;
    }
    final Object? thread = args['thread'];
    final Object? answer = args['answer'];
    final List<UploadItem> files = <UploadItem>[];
    final List<String> ids = <String>[];
    for (final Object? f in (args['files'] as List<dynamic>? ?? const <dynamic>[])) {
      final Map<String, dynamic> m = asMap(f);
      ids.add(str(m['id']));
      files.add(ChatFiles.items[str(m['id'])] ?? UploadItem(path: str(m['path']), name: str(m['name'])));
    }
    return QueuedChat(
      messageId: targetId,
      threadId: str(args['threadId']),
      text: str(args['text']),
      createdAt: intOf(args['createdAt']),
      files: files,
      fileIds: ids,
      newThread: thread is Map,
      threadTitle: thread is Map ? strOrNull(thread['title']) : null,
      threadAbout: thread is Map ? ThreadAbout.fromJson(thread['about']) : null,
      context: ChatContext.fromJson(args['context']),
      answer: answer is Map ? ChatAnswer(turnId: str(answer['turnId']), id: str(answer['id'])) : null,
    );
  }
}

/// The server's goals with the waiting writes applied on top, so a change that
/// is still in the outbox is never overwritten by a subscription update.
List<Goal> overlayGoals(List<Goal> server, List<OutboxOp> ops) {
  final List<Goal> out = List<Goal>.from(server);
  for (final OutboxOp op in ops) {
    final int i = out.indexWhere((Goal g) => g.id == op.targetId);
    switch (op.type) {
      case OutboxOp.goalCreate:
        if (i < 0) {
          out.add(Goal(
            id: op.targetId,
            title: str(op.args['title']),
            kind: str(op.args['kind'], 'custom'),
            status: 'active',
            source: 'user',
            createdAt: intOf(op.args['createdAt']),
            exercise: strOrNull(op.args['exercise']),
            targetKg: dblOrNull(op.args['targetKg']),
            sessionsPerWeek: intOrNull(op.args['sessionsPerWeek']),
          ));
        }
      case OutboxOp.goalUpdate:
        if (i >= 0) {
          out[i] = GoalPatch.fromJson(asMap(op.args['patch'])).applyTo(out[i]);
        }
      case OutboxOp.goalRemove:
        if (i >= 0) {
          out.removeAt(i);
        }
    }
  }
  return out;
}

/// Same as [overlayGoals], for context notes.
List<ContextItem> overlayContext(List<ContextItem> server, List<OutboxOp> ops) {
  final List<ContextItem> out = List<ContextItem>.from(server);
  for (final OutboxOp op in ops) {
    final int i = out.indexWhere((ContextItem c) => c.id == op.targetId);
    switch (op.type) {
      case OutboxOp.contextCreate:
        if (i < 0) {
          out.add(ContextItem(
            id: op.targetId,
            text: str(op.args['text']),
            topic: str(op.args['topic']),
            active: true,
            source: 'user',
            createdAt: intOf(op.args['createdAt']),
          ));
        }
      case OutboxOp.contextUpdate:
        if (i >= 0) {
          out[i] = ContextPatch.fromJson(asMap(op.args['patch'])).applyTo(out[i]);
        }
      case OutboxOp.contextRemove:
        if (i >= 0) {
          out.removeAt(i);
        }
    }
  }
  return out;
}
