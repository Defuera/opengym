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
  Stream<OpenRemote> watchOpenSession() => _proxy((ConvexClient c) => c.watchOpenSession());

  @override
  Future<int> putOpenSession(Map<String, dynamic> session) {
    final ConvexClient? c = _inner;
    return c == null ? Future<int>.error(const ConvexCallException.notConfigured()) : c.putOpenSession(session);
  }

  @override
  Future<void> clearOpenSession(String id) => _call((ConvexClient c) => c.clearOpenSession(id));

  @override
  Stream<List<Session>> watchSessionsSince(int since) =>
      _proxy((ConvexClient c) => c.watchSessionsSince(since));

  @override
  Stream<List<Goal>> watchGoals() => _proxy((ConvexClient c) => c.watchGoals());

  @override
  Stream<List<LogEntry>> watchEntries({int limit = 50}) =>
      _proxy((ConvexClient c) => c.watchEntries(limit: limit));

  @override
  Stream<List<Place>> watchPlaces() => _proxy((ConvexClient c) => c.watchPlaces());

  @override
  Stream<List<ExerciseArt>> watchExerciseArt(List<String> names) =>
      _proxy((ConvexClient c) => c.watchExerciseArt(names));

  @override
  Future<void> requestExerciseArt(List<String> names) =>
      _call((ConvexClient c) => c.requestExerciseArt(names));

  @override
  Future<void> saveEntry({
    required String entryId,
    required String text,
    required List<String> fileIds,
    required int at,
    required int createdAt,
  }) =>
      _call((ConvexClient c) =>
          c.saveEntry(entryId: entryId, text: text, fileIds: fileIds, at: at, createdAt: createdAt));

  @override
  Future<void> removeEntry(String entryId) => _call((ConvexClient c) => c.removeEntry(entryId));

  @override
  Stream<List<ContextItem>> watchContext() => _proxy((ConvexClient c) => c.watchContext());

  @override
  Stream<Stored<Plan>> watchNextPlan({String? activity, String? focus}) =>
      _proxy((ConvexClient c) => c.watchNextPlan(activity: activity, focus: focus));

  @override
  Stream<StartRequest?> watchStartRequest(String requestId) =>
      _proxy((ConvexClient c) => c.watchStartRequest(requestId));

  @override
  Future<void> requestStart({
    required String requestId,
    String? name,
    String? text,
    String? feedback,
    String? previousRequestId,
    List<Map<String, dynamic>>? previousPlan,
  }) =>
      _call((ConvexClient c) => c.requestStart(
            requestId: requestId,
            name: name,
            text: text,
            feedback: feedback,
            previousRequestId: previousRequestId,
            previousPlan: previousPlan,
          ));

  @override
  Stream<List<Program>> watchPrograms() => _proxy((ConvexClient c) => c.watchPrograms());

  @override
  Stream<List<Proposal>> watchThreadProposals(String threadId) =>
      _proxy((ConvexClient c) => c.watchThreadProposals(threadId));

  @override
  Future<String> acceptProposal(String proposalId) {
    final ConvexClient? c = _inner;
    if (c == null) {
      return Future<String>.error(const ConvexCallException.notConfigured());
    }
    return c.acceptProposal(proposalId);
  }

  @override
  Future<void> declineProposal(String proposalId) => _call((ConvexClient c) => c.declineProposal(proposalId));

  @override
  Future<void> setProgramStatus(String programId, String status) =>
      _call((ConvexClient c) => c.setProgramStatus(programId, status));

  @override
  Future<void> removeProgram(String programId) => _call((ConvexClient c) => c.removeProgram(programId));

  @override
  Stream<Stored<Dashboard>> watchDashboard(int days) =>
      _proxy((ConvexClient c) => c.watchDashboard(days));

  @override
  Stream<Stored<Review?>> watchReview(String sessionId) =>
      _proxy((ConvexClient c) => c.watchReview(sessionId));

  @override
  Stream<Map<String, int>?> watchSessionLoad(String sessionId) =>
      _proxy((ConvexClient c) => c.watchSessionLoad(sessionId));

  @override
  Future<Map<String, int>?> planLoad(List<PlanLoadItem> exercises) {
    final ConvexClient? c = _inner;
    if (c == null) {
      return Future<Map<String, int>?>.error(const ConvexCallException.notConfigured());
    }
    return c.planLoad(exercises);
  }

  @override
  Stream<List<ImportJob>> watchImports() => _proxy((ConvexClient c) => c.watchImports());

  @override
  Stream<AboutMe> watchAboutMe() => _proxy((ConvexClient c) => c.watchAboutMe());

  @override
  Stream<AiSettings> watchAiSettings() => _proxy((ConvexClient c) => c.watchAiSettings());

  @override
  Future<void> setAiModel(String? model) => _call((ConvexClient c) => c.setAiModel(model));

  @override
  Future<void> refreshModels() => _call((ConvexClient c) => c.refreshModels());

  @override
  Future<List<AskItem>> askAfter(String sessionId) {
    final ConvexClient? c = _inner;
    if (c == null) {
      return Future<List<AskItem>>.error(const ConvexCallException.notConfigured());
    }
    return c.askAfter(sessionId);
  }

  @override
  Future<void> saveLimit(Limit limit) => _call((ConvexClient c) => c.saveLimit(limit));

  @override
  Future<void> removeLimit(String limitId) => _call((ConvexClient c) => c.removeLimit(limitId));

  @override
  Future<void> addRecord(LimitRecord record) => _call((ConvexClient c) => c.addRecord(record));

  @override
  Future<void> removeRecord(String recordId) => _call((ConvexClient c) => c.removeRecord(recordId));

  @override
  Future<void> saveCheckin(Checkin checkin) => _call((ConvexClient c) => c.saveCheckin(checkin));

  @override
  Stream<List<Thread>> watchThreads() => _proxy((ConvexClient c) => c.watchThreads());

  @override
  Stream<List<Message>> watchMessages(String threadId) =>
      _proxy((ConvexClient c) => c.watchMessages(threadId));

  @override
  Future<void> saveSession(Session session) => _call((ConvexClient c) => c.saveSession(session));

  @override
  Future<void> setSessionPlace({required String sessionId, required String? placeId}) =>
      _call((ConvexClient c) => c.setSessionPlace(sessionId: sessionId, placeId: placeId));

  @override
  Future<void> logSessionText({
    required String sessionId,
    required String type,
    required String text,
    required int at,
  }) =>
      _call((ConvexClient c) => c.logSessionText(sessionId: sessionId, type: type, text: text, at: at));

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
  Future<void> createThread({required String threadId, String? title, String? placeId, ThreadAbout? about}) =>
      _call((ConvexClient c) => c.createThread(threadId: threadId, title: title, placeId: placeId, about: about));

  @override
  Future<void> renameThread({required String threadId, required String title}) =>
      _call((ConvexClient c) => c.renameThread(threadId: threadId, title: title));

  @override
  Future<void> removeThread(String threadId) => _call((ConvexClient c) => c.removeThread(threadId));

  @override
  Future<void> sendMessage({
    required String threadId,
    required String messageId,
    required String text,
    List<String> fileIds = const <String>[],
    ChatContext? context,
    ChatAnswer? answer,
  }) {
    return _call((ConvexClient c) => c.sendMessage(
        threadId: threadId, messageId: messageId, text: text, fileIds: fileIds, context: context, answer: answer));
  }

  @override
  Future<void> sendVoice({
    required String threadId,
    required String messageId,
    required String fileId,
  }) {
    return _call((ConvexClient c) => c.sendVoice(threadId: threadId, messageId: messageId, fileId: fileId));
  }

  @override
  Future<void> retryVoice(String messageId) => _call((ConvexClient c) => c.retryVoice(messageId));

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
