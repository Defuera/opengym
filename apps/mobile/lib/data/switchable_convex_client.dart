import 'dart:async';

import '../models.dart';
import 'convex_client.dart';

/// A [ConvexClient] whose address and token can change while the app runs.
///
/// Stores subscribe once. When Settings change, every open stream moves to
/// the new connection by itself. With no address or token, streams stay quiet
/// and commands fail with a transient "not configured" error, so the outbox
/// keeps its writes.
class SwitchableConvexClient implements ConvexClient {
  SwitchableConvexClient(this._factory);

  final ConvexClient Function(String url, String token) _factory;

  ConvexClient? _inner;
  ConvexLink _link = ConvexLink.notConfigured;
  StreamSubscription<ConvexLink>? _linkSub;
  final StreamController<void> _swaps = StreamController<void>.broadcast(sync: true);
  final StreamController<ConvexLink> _links = StreamController<ConvexLink>.broadcast(sync: true);

  bool get configured => _inner != null;

  /// Point at a deployment. Empty or unusable values mean "not configured".
  Future<void> configure(String url, String token) async {
    final ConvexClient? old = _inner;
    await _linkSub?.cancel();
    _linkSub = null;
    ConvexClient? next;
    if (url.trim().isNotEmpty && token.trim().isNotEmpty && isUsableServerUrl(url)) {
      next = _factory(url.trim(), token.trim());
    }
    _inner = next;
    if (next == null) {
      _setLink(ConvexLink.notConfigured);
    } else {
      _setLink(ConvexLink.connecting);
      _linkSub = next.connection.listen(_setLink);
    }
    _swaps.add(null);
    await old?.dispose();
  }

  void _setLink(ConvexLink l) {
    _link = l;
    _links.add(l);
  }

  @override
  Stream<ConvexLink> get connection =>
      Stream<ConvexLink>.multi((MultiStreamController<ConvexLink> c) {
        c.addSync(_link);
        final StreamSubscription<ConvexLink> s = _links.stream.listen(c.addSync);
        c.onCancel = s.cancel;
      });

  Stream<T> _proxy<T>(Stream<T> Function(ConvexClient c) open) {
    late final StreamController<T> out;
    StreamSubscription<T>? sub;
    StreamSubscription<void>? swap;
    void attach() {
      sub?.cancel();
      sub = null;
      final ConvexClient? c = _inner;
      if (c != null) {
        sub = open(c).listen(out.add, onError: out.addError);
      }
    }

    out = StreamController<T>(
      onListen: () {
        attach();
        swap = _swaps.stream.listen((_) => attach());
      },
      onCancel: () async {
        await swap?.cancel();
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  Future<void> _call(Future<void> Function(ConvexClient c) run) {
    final ConvexClient? c = _inner;
    if (c == null) {
      return Future<void>.error(const ConvexCallException.notConfigured());
    }
    return run(c);
  }

  @override
  Stream<List<Session>> watchRecentSessions({int limit = 200}) =>
      _proxy((ConvexClient c) => c.watchRecentSessions(limit: limit));

  @override
  Stream<List<Session>> watchSessionsSince(int since) =>
      _proxy((ConvexClient c) => c.watchSessionsSince(since));

  @override
  Stream<List<Goal>> watchGoals() => _proxy((ConvexClient c) => c.watchGoals());

  @override
  Stream<List<ContextItem>> watchContext() => _proxy((ConvexClient c) => c.watchContext());

  @override
  Stream<Stored<Plan>> watchNextPlan(String type) =>
      _proxy((ConvexClient c) => c.watchNextPlan(type));

  @override
  Stream<Stored<List<Prediction>>> watchPredictions() =>
      _proxy((ConvexClient c) => c.watchPredictions());

  @override
  Stream<Stored<Dashboard>> watchDashboard(int days) =>
      _proxy((ConvexClient c) => c.watchDashboard(days));

  @override
  Stream<Stored<Review?>> watchReview(String sessionId) =>
      _proxy((ConvexClient c) => c.watchReview(sessionId));

  @override
  Stream<List<ImportJob>> watchImports() => _proxy((ConvexClient c) => c.watchImports());

  @override
  Stream<List<Thread>> watchThreads() => _proxy((ConvexClient c) => c.watchThreads());

  @override
  Stream<List<Message>> watchMessages(String threadId) =>
      _proxy((ConvexClient c) => c.watchMessages(threadId));

  @override
  Future<void> saveSession(Session session) => _call((ConvexClient c) => c.saveSession(session));

  @override
  Future<void> removeSession(String sessionId) =>
      _call((ConvexClient c) => c.removeSession(sessionId));

  @override
  Future<void> createGoal({
    required String goalId,
    required String title,
    required String kind,
    String? exercise,
    double? targetKg,
    int? sessionsPerWeek,
  }) {
    return _call((ConvexClient c) => c.createGoal(
          goalId: goalId,
          title: title,
          kind: kind,
          exercise: exercise,
          targetKg: targetKg,
          sessionsPerWeek: sessionsPerWeek,
        ));
  }

  @override
  Future<void> updateGoal(String goalId, GoalPatch patch) =>
      _call((ConvexClient c) => c.updateGoal(goalId, patch));

  @override
  Future<void> removeGoal(String goalId) => _call((ConvexClient c) => c.removeGoal(goalId));

  @override
  Future<void> createContext({
    required String itemId,
    required String text,
    required String topic,
  }) {
    return _call((ConvexClient c) => c.createContext(itemId: itemId, text: text, topic: topic));
  }

  @override
  Future<void> updateContext(String itemId, ContextPatch patch) =>
      _call((ConvexClient c) => c.updateContext(itemId, patch));

  @override
  Future<void> removeContext(String itemId) => _call((ConvexClient c) => c.removeContext(itemId));

  @override
  Future<void> removeImport(String importId) => _call((ConvexClient c) => c.removeImport(importId));

  @override
  Future<void> createThread({required String threadId, required String title}) =>
      _call((ConvexClient c) => c.createThread(threadId: threadId, title: title));

  @override
  Future<void> removeThread(String threadId) => _call((ConvexClient c) => c.removeThread(threadId));

  @override
  Future<void> sendMessage({
    required String threadId,
    required String messageId,
    required String text,
    List<String> fileIds = const <String>[],
  }) {
    return _call((ConvexClient c) =>
        c.sendMessage(threadId: threadId, messageId: messageId, text: text, fileIds: fileIds));
  }

  @override
  Future<FileMeta> uploadFile({
    required String fileId,
    required String name,
    required String mime,
    required List<int> bytes,
  }) {
    final ConvexClient? c = _inner;
    if (c == null) {
      return Future<FileMeta>.error(const ConvexCallException.notConfigured());
    }
    return c.uploadFile(fileId: fileId, name: name, mime: mime, bytes: bytes);
  }

  @override
  Future<FileLink?> fileLink(String fileId) {
    final ConvexClient? c = _inner;
    if (c == null) {
      return Future<FileLink?>.error(const ConvexCallException.notConfigured());
    }
    return c.fileLink(fileId);
  }

  @override
  Future<void> removeFile(String fileId) => _call((ConvexClient c) => c.removeFile(fileId));

  @override
  Future<void> startImport({required String importId, required List<String> fileIds}) =>
      _call((ConvexClient c) => c.startImport(importId: importId, fileIds: fileIds));

  @override
  Future<AccessStatus> checkAccess() async {
    final ConvexClient? c = _inner;
    return c == null ? AccessStatus.notConfigured : c.checkAccess();
  }

  @override
  Future<void> dispose() async {
    await _linkSub?.cancel();
    await _inner?.dispose();
    _inner = null;
  }
}
