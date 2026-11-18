import 'dart:async';

import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';

/// A value the fake pushes: the latest value is replayed to new listeners.
class Live<T> {
  Live([this.value]);

  T? value;
  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);

  void set(T v) {
    value = v;
    _changes.add(null);
  }

  Stream<T> stream() => Stream<T>.multi((MultiStreamController<T> c) {
        final T? v = value;
        if (v != null) {
          c.addSync(v);
        }
        final StreamSubscription<void> s = _changes.stream.listen((_) {
          final T? n = value;
          if (n != null) {
            c.addSync(n);
          }
        });
        // Do not hand the cancel future back: it never completes under a widget test's fake clock.
        c.onCancel = () {
          s.cancel();
        };
      });

  void error(Object e) => _changes.addError(e);
}

/// In-memory stand-in for the backend. Holds "server" state, pushes it like a
/// live query, and logs every command in [calls].
class FakeConvexClient implements ConvexClient {
  /// When false every command fails with a transient error.
  bool online = true;

  /// When set, the next command fails with this error.
  ConvexCallException? failNext;

  /// Commands (as logged in [calls]) that always fail with a fault that has no data.
  final Set<String> poison = <String>{};
  AccessStatus access = AccessStatus.ok;

  final List<String> calls = <String>[];
  final Map<String, Session> serverSessions = <String, Session>{};
  final Map<String, Goal> serverGoals = <String, Goal>{};
  final Map<String, ContextItem> serverContext = <String, ContextItem>{};
  final Map<String, ImportJob> serverImports = <String, ImportJob>{};
  final Map<String, Thread> serverThreads = <String, Thread>{};
  final Map<String, List<Message>> serverMessages = <String, List<Message>>{};
  final Map<String, FileMeta> serverFiles = <String, FileMeta>{};

  /// Notes as the server stores them: file ids, the files are looked up in [serverFiles].
  final Map<String, ({String text, List<String> fileIds, int at, int createdAt})> serverEntries =
      <String, ({String text, List<String> fileIds, int at, int createdAt})>{};

  /// When set, [sendMessage] waits for it before the server stores anything.
  Completer<void>? sendGate;

  /// When set, [uploadFile] waits for it first.
  Completer<void>? uploadGate;

  /// Set to make [uploadFile] fail once.
  ConvexCallException? failUpload;

  final Live<List<Session>> _sessions = Live<List<Session>>(<Session>[]);
  final Live<List<LogEntry>> _entries = Live<List<LogEntry>>(<LogEntry>[]);
  final Live<List<Goal>> _goals = Live<List<Goal>>(<Goal>[]);
  final Live<List<ContextItem>> _context = Live<List<ContextItem>>(<ContextItem>[]);
  final Live<AboutMe> about = Live<AboutMe>(const AboutMe());

  /// The coach model setting the fake serves. [setAiModel] changes it; [refreshModels] swaps in [modelsOnRefresh].
  final Live<AiSettings> aiSettings = Live<AiSettings>(const AiSettings());
  List<String> modelsOnRefresh = <String>[];

  /// What [askAfter] answers per session id.
  final Map<String, List<AskItem>> asks = <String, List<AskItem>>{};
  final Live<List<ImportJob>> _imports = Live<List<ImportJob>>(<ImportJob>[]);
  final Map<String, Live<Stored<Plan>>> plans = <String, Live<Stored<Plan>>>{};
  final Map<int, Live<Stored<Dashboard>>> dashboards = <int, Live<Stored<Dashboard>>>{};
  final Map<String, Live<Map<String, int>?>> loads = <String, Live<Map<String, int>?>>{};
  final Map<String, Live<Stored<Review?>>> reviews = <String, Live<Stored<Review?>>>{};
  final StreamController<ConvexLink> link = StreamController<ConvexLink>.broadcast(sync: true);
  ConvexLink linkNow = ConvexLink.connected;
  bool disposed = false;

  void _publish() {
    final List<Session> s = serverSessions.values.toList()
      ..sort((Session a, Session b) => b.when.compareTo(a.when));
    _sessions.set(s);
    _goals.set(serverGoals.values.toList());
    final List<LogEntry> e = <LogEntry>[
      for (final MapEntry<String, ({String text, List<String> fileIds, int at, int createdAt})> x
          in serverEntries.entries)
        LogEntry(id: x.key, text: x.value.text, at: x.value.at, createdAt: x.value.createdAt, files: <EntryFile>[
          for (final String f in x.value.fileIds)
            if (serverFiles[f] != null)
              EntryFile(
                  id: f,
                  name: serverFiles[f]!.name,
                  mime: serverFiles[f]!.mime,
                  size: serverFiles[f]!.size,
                  kind: serverFiles[f]!.mime.startsWith('image/') ? 'image' : serverFiles[f]!.kind,
                  createdAt: serverFiles[f]!.createdAt,
                  url: 'https://files.test/$f'),
        ]),
    ]..sort((LogEntry a, LogEntry b) => b.at.compareTo(a.at));
    _entries.set(e);
    _context.set(serverContext.values.toList());
    _imports.set(serverImports.values.toList());
    final List<Thread> t = serverThreads.values.toList()
      ..sort((Thread a, Thread b) => b.updatedAt.compareTo(a.updatedAt));
    _threads.set(t);
    for (final MapEntry<String, List<Message>> e in serverMessages.entries) {
      _messages.putIfAbsent(e.key, () => Live<List<Message>>()).set(List<Message>.from(e.value));
    }
  }

  final Live<List<Thread>> _threads = Live<List<Thread>>(<Thread>[]);
  final Map<String, Live<List<Message>>> _messages = <String, Live<List<Message>>>{};
  int _clock = 1000;

  /// The coach answers: stores the assistant message, thread goes idle.
  void coachAnswers(String threadId, String text, {List<String> sources = const <String>[]}) {
    serverChanged(() {
      serverMessages.putIfAbsent(threadId, () => <Message>[]).add(Message(
          id: 'a${++_clock}',
          threadId: threadId,
          role: 'assistant',
          text: text,
          createdAt: ++_clock,
          sources: sources));
      _setThread(threadId, status: 'idle', lastMessage: text);
    });
  }

  /// The coach job failed.
  void coachFails(String threadId, String error) {
    serverChanged(() => _setThread(threadId, status: 'failed', error: error));
  }

  void _setThread(String id, {required String status, String? error, String? lastMessage}) {
    final Thread t = serverThreads[id]!;
    serverThreads[id] = Thread(
      id: t.id,
      title: t.title,
      titleSource: t.titleSource,
      createdAt: t.createdAt,
      updatedAt: ++_clock,
      summary: t.summary,
      lastMessage: lastMessage ?? t.lastMessage,
      status: status,
      error: error,
      pending: status == 'thinking' ? 1 : 0,
    );
  }

  /// A change that happens on the server, not through this client.
  void serverChanged(void Function() change) {
    change();
    _publish();
  }

  void setLink(ConvexLink l) {
    linkNow = l;
    link.add(l);
  }

  void _command(String name) {
    final ConvexCallException? f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
    if (!online) {
      throw const ConvexCallException.unreachable();
    }
    if (poison.contains(name)) {
      throw const ConvexCallException('The server could not finish that. The app will try again.');
    }
    calls.add(name);
  }

  @override
  Stream<ConvexLink> get connection =>
      Stream<ConvexLink>.multi((MultiStreamController<ConvexLink> c) {
        c.addSync(linkNow);
        final StreamSubscription<ConvexLink> s = link.stream.listen(c.addSync);
        c.onCancel = s.cancel;
      });

  @override
  Stream<List<Session>> watchRecentSessions({int limit = 200}) => _sessions.stream();

  @override
  Stream<List<Session>> watchSessionsSince(int since) => _sessions.stream();

  @override
  Stream<List<Goal>> watchGoals() => _goals.stream();

  @override
  Stream<List<LogEntry>> watchEntries({int limit = 50}) => _entries.stream();

  @override
  Future<void> saveEntry({
    required String entryId,
    required String text,
    required List<String> fileIds,
    required int at,
    required int createdAt,
  }) async {
    _command('saveEntry:$entryId');
    final List<String> before = serverEntries[entryId]?.fileIds ?? <String>[];
    for (final String f in before) {
      if (!fileIds.contains(f)) {
        serverFiles.remove(f);
      }
    }
    serverEntries[entryId] = (text: text, fileIds: fileIds, at: at, createdAt: createdAt);
    _publish();
  }

  @override
  Future<void> removeEntry(String entryId) async {
    _command('removeEntry:$entryId');
    final entry = serverEntries.remove(entryId);
    for (final String f in entry?.fileIds ?? <String>[]) {
      serverFiles.remove(f);
    }
    _publish();
  }

  @override
  Stream<List<ContextItem>> watchContext() => _context.stream();

  /// Key of [plans]: the focus alone for the default activity, else
  /// `activity/focus`.
  static String planKey({String? activity, String? focus}) =>
      activity == null ? (focus ?? '') : '$activity/${focus ?? ''}';

  @override
  Stream<Stored<Plan>> watchNextPlan({String? activity, String? focus}) {
    final String key = planKey(activity: activity, focus: focus);
    return plans.putIfAbsent(key, () => Live<Stored<Plan>>()).stream();
  }

  /// Start requests the app sent, in order: id and text.
  final List<(String, String?)> startSent = <(String, String?)>[];
  final List<String?> startNames = <String?>[];

  final Map<String, Live<StartRequest?>> startRequests = <String, Live<StartRequest?>>{};

  String get lastStartId => startSent.last.$1;

  /// The server answers the last start request.
  void answerStart(StartRequest r) =>
      startRequests.putIfAbsent(lastStartId, () => Live<StartRequest?>()).set(r);

  @override
  Future<void> requestStart({
    required String requestId,
    String? name,
    String? text,
  }) async {
    _command('requestStart:$requestId');
    startSent.add((requestId, text));
    startNames.add(name);
    startRequests.putIfAbsent(requestId, () => Live<StartRequest?>());
  }

  @override
  Stream<StartRequest?> watchStartRequest(String requestId) =>
      startRequests.putIfAbsent(requestId, () => Live<StartRequest?>()).stream();

  @override
  Stream<Stored<Dashboard>> watchDashboard(int days) =>
      dashboards.putIfAbsent(days, () => Live<Stored<Dashboard>>()).stream();

  @override
  Stream<Stored<Review?>> watchReview(String sessionId) =>
      reviews.putIfAbsent(sessionId, () => Live<Stored<Review?>>()).stream();

  @override
  Stream<Map<String, int>?> watchSessionLoad(String sessionId) =>
      loads.putIfAbsent(sessionId, () => Live<Map<String, int>?>()).stream();

  @override
  Stream<List<ImportJob>> watchImports() => _imports.stream();

  @override
  Stream<AboutMe> watchAboutMe() => about.stream();

  @override
  Stream<AiSettings> watchAiSettings() => aiSettings.stream();

  @override
  Future<void> setAiModel(String? model) async {
    _command('setAiModel:${model ?? 'default'}');
    aiSettings.set(aiSettings.value!.withOverride(model));
  }

  @override
  Future<void> refreshModels() async {
    _command('refreshModels');
    final AiSettings a = aiSettings.value!;
    aiSettings.set(AiSettings(
      provider: a.provider,
      defaultModel: a.defaultModel,
      model: a.model,
      override: a.override,
      models: modelsOnRefresh,
      fetchedAt: DateTime(2026, 11, 17, 20, 50),
    ));
  }

  @override
  Future<List<AskItem>> askAfter(String sessionId) async {
    _command('askAfter:$sessionId');
    return asks[sessionId] ?? <AskItem>[];
  }

  @override
  Future<void> saveLimit(Limit limit) async {
    _command('saveLimit:${limit.id}');
    final AboutMe a = about.value ?? const AboutMe();
    final Limit? old = a.limitById(limit.id);
    about.set(a.copyWith(limits: <Limit>[
      for (final Limit l in a.limits)
        if (l.id != limit.id) l,
      limit.copyWith(records: old?.records, checkins: old?.checkins),
    ]));
  }

  @override
  Future<void> removeLimit(String limitId) async {
    _command('removeLimit:$limitId');
    final AboutMe a = about.value ?? const AboutMe();
    about.set(a.copyWith(limits: <Limit>[for (final Limit l in a.limits) if (l.id != limitId) l]));
  }

  @override
  Future<void> addRecord(LimitRecord record) async {
    _command('addRecord:${record.id}');
    final AboutMe a = about.value ?? const AboutMe();
    about.set(a.copyWith(limits: <Limit>[
      for (final Limit l in a.limits)
        if (l.id == record.limitId)
          l.copyWith(records: <LimitRecord>[
            for (final LimitRecord r in l.records)
              if (r.id != record.id) r,
            record,
          ])
        else
          l,
    ]));
  }

  @override
  Future<void> removeRecord(String recordId) async {
    _command('removeRecord:$recordId');
    final AboutMe a = about.value ?? const AboutMe();
    about.set(a.copyWith(limits: <Limit>[
      for (final Limit l in a.limits)
        l.copyWith(records: <LimitRecord>[
          for (final LimitRecord r in l.records)
            if (r.id != recordId) r,
        ]),
    ]));
  }

  @override
  Future<void> saveCheckin(Checkin checkin) async {
    _command('saveCheckin:${checkin.id}');
    final AboutMe a = about.value ?? const AboutMe();
    about.set(a.copyWith(limits: <Limit>[
      for (final Limit l in a.limits)
        if (l.id == checkin.limitId)
          l.copyWith(checkins: <Checkin>[
            checkin,
            for (final Checkin c in l.checkins)
              if (c.id != checkin.id) c,
          ])
        else
          l,
    ]));
  }

  @override
  Stream<List<Thread>> watchThreads() => _threads.stream();

  @override
  Stream<List<Message>> watchMessages(String threadId) =>
      _messages.putIfAbsent(threadId, () => Live<List<Message>>(<Message>[])).stream();

  @override
  Future<void> createThread({required String threadId, String? title}) async {
    _command('createThread:$threadId');
    serverThreads.putIfAbsent(
        threadId,
        () => Thread(
              id: threadId,
              title: title ?? 'New chat',
              titleSource: title == null ? 'auto' : 'user',
              createdAt: ++_clock,
              updatedAt: _clock,
            ));
    _publish();
  }

  @override
  Future<void> renameThread({required String threadId, required String title}) async {
    _command('renameThread:$threadId');
    final Thread? t = serverThreads[threadId];
    if (t != null) {
      _replaceThread(t, title: title, titleSource: 'user');
    }
    _publish();
  }

  /// The backend's AI title arrives. Like the real backend, it never replaces a title the user set.
  void aiTitle(String threadId, String title) {
    serverChanged(() {
      final Thread? t = serverThreads[threadId];
      if (t != null && t.titleSource == 'auto') {
        _replaceThread(t, title: title, titleSource: 'auto');
      }
    });
  }

  void _replaceThread(Thread t, {required String title, required String titleSource}) {
    serverThreads[t.id] = Thread(
      id: t.id,
      title: title,
      titleSource: titleSource,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
      summary: t.summary,
      lastMessage: t.lastMessage,
      status: t.status,
      error: t.error,
      pending: t.pending,
    );
  }

  @override
  Future<void> removeThread(String threadId) async {
    _command('removeThread:$threadId');
    serverThreads.remove(threadId);
    serverMessages.remove(threadId);
    _publish();
  }

  @override
  Future<void> sendMessage({
    required String threadId,
    required String messageId,
    required String text,
    List<String> fileIds = const <String>[],
  }) async {
    _command('sendMessage:$messageId');
    final Completer<void>? gate = sendGate;
    if (gate != null) {
      await gate.future;
    }
    final List<Message> list = serverMessages.putIfAbsent(threadId, () => <Message>[]);
    if (list.any((Message m) => m.id == messageId)) {
      return; // the server ignores a resend
    }
    list.add(Message(
        id: messageId,
        threadId: threadId,
        role: 'user',
        text: text,
        createdAt: ++_clock,
        fileIds: fileIds));
    if (list.length == 1) {
      final Thread t = serverThreads[threadId]!;
      if (t.titleSource == 'auto') {
        final String cut = text.length > 40 ? text.substring(0, 40) : text;
        _replaceThread(t, title: cut[0].toUpperCase() + cut.substring(1), titleSource: 'auto');
      }
    }
    _setThread(threadId, status: 'thinking');
    _publish();
  }

  @override
  Future<FileMeta> uploadFile({
    required String fileId,
    required String name,
    required String mime,
    required List<int> bytes,
  }) async {
    await uploadGate?.future;
    final ConvexCallException? f = failUpload;
    if (f != null) {
      failUpload = null;
      throw f;
    }
    _command('uploadFile:$fileId');
    return serverFiles.putIfAbsent(
        fileId,
        () => FileMeta(
            id: fileId,
            name: name,
            mime: mime,
            size: bytes.length,
            kind: 'text',
            createdAt: ++_clock));
  }

  @override
  Future<FileLink?> fileLink(String fileId) async {
    final FileMeta? m = serverFiles[fileId];
    return m == null ? null : FileLink(m, 'https://files.test/$fileId');
  }

  @override
  Future<void> removeFile(String fileId) async {
    _command('removeFile:$fileId');
    serverFiles.remove(fileId);
  }

  @override
  Future<void> startImport({required String importId, required List<String> fileIds}) async {
    _command('startImport:$importId');
    serverImports.putIfAbsent(
        importId,
        () => ImportJob(
            id: importId,
            status: 'running',
            total: fileIds.length,
            processed: 0,
            counts: const ImportCounts(),
            notes: const <String>[],
            createdAt: ++_clock));
    _publish();
  }

  /// The server moves an import forward (a job running in the background).
  void importProgress(String importId,
      {int? processed, ImportCounts? counts, List<String>? notes, String? status}) {
    serverChanged(() {
      final ImportJob j = serverImports[importId]!;
      serverImports[importId] = ImportJob(
        id: j.id,
        status: status ?? j.status,
        total: j.total,
        processed: processed ?? j.processed,
        counts: counts ?? j.counts,
        notes: notes ?? j.notes,
        createdAt: j.createdAt,
      );
    });
  }

  @override
  Future<void> saveSession(Session session) async {
    _command('saveSession:${session.id}');
    serverSessions[session.id] = session;
    _publish();
  }

  /// Session ids of `logSessionText` calls: id -> (type, text, at). The fake
  /// stores the session as the server does (pending); a test lets the "job"
  /// finish with [finishParse].
  final Map<String, (String, String, int)> loggedTexts = <String, (String, String, int)>{};

  @override
  Future<void> logSessionText({
    required String sessionId,
    required String type,
    required String text,
    required int at,
  }) async {
    _command('logSessionText:$sessionId');
    loggedTexts.putIfAbsent(sessionId, () => (type, text, at));
    serverSessions.putIfAbsent(
      sessionId,
      () => Session(
        id: sessionId,
        kind: 'activity',
        type: type,
        startedAt: at,
        endedAt: at,
        note: text,
        parse: 'pending',
      ),
    );
    _publish();
  }

  /// The server's parse_log job has written its result into the session.
  void finishParse(String sessionId, {int? minutes, double? km, String parse = 'done'}) {
    serverChanged(() {
      final Session s = serverSessions[sessionId]!;
      serverSessions[sessionId] = Session(
        id: s.id,
        kind: s.kind,
        type: s.type,
        startedAt: s.startedAt,
        endedAt: s.endedAt,
        minutes: minutes,
        distanceKm: km,
        note: s.note,
        parse: parse,
      );
    });
  }

  @override
  Future<void> removeSession(String sessionId) async {
    _command('removeSession:$sessionId');
    serverSessions.remove(sessionId);
    _publish();
  }

  @override
  Future<void> createGoal({
    required String goalId,
    required String title,
    required String kind,
    String? exercise,
    double? targetKg,
    int? sessionsPerWeek,
  }) async {
    _command('createGoal:$goalId');
    serverGoals.putIfAbsent(
      goalId,
      () => Goal(
        id: goalId,
        title: title,
        kind: kind,
        status: 'active',
        source: 'user',
        createdAt: 1,
        exercise: exercise,
        targetKg: targetKg,
        sessionsPerWeek: sessionsPerWeek,
      ),
    );
    _publish();
  }

  @override
  Future<void> updateGoal(String goalId, GoalPatch patch) async {
    _command('updateGoal:$goalId');
    final Goal? g = serverGoals[goalId];
    if (g == null) {
      throw const ConvexCallException('goal not found', kind: ConvexFailure.rejected);
    }
    serverGoals[goalId] = patch.applyTo(g);
    _publish();
  }

  @override
  Future<void> removeGoal(String goalId) async {
    _command('removeGoal:$goalId');
    serverGoals.remove(goalId);
    _publish();
  }

  @override
  Future<void> createContext({
    required String itemId,
    required String text,
    required String topic,
  }) async {
    _command('createContext:$itemId');
    serverContext.putIfAbsent(
      itemId,
      () => ContextItem(
          id: itemId, text: text, topic: topic, active: true, source: 'user', createdAt: 1),
    );
    _publish();
  }

  @override
  Future<void> updateContext(String itemId, ContextPatch patch) async {
    _command('updateContext:$itemId');
    final ContextItem? c = serverContext[itemId];
    if (c != null) {
      serverContext[itemId] = patch.applyTo(c);
    }
    _publish();
  }

  @override
  Future<void> removeContext(String itemId) async {
    _command('removeContext:$itemId');
    serverContext.remove(itemId);
    _publish();
  }

  @override
  Future<void> removeImport(String importId) async {
    _command('removeImport:$importId');
    serverImports.remove(importId);
    serverSessions.removeWhere((String _, Session s) => s.importId == importId);
    _publish();
  }

  @override
  Future<AccessStatus> checkAccess() async => access;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

Goal goalFixture([String id = 'g']) =>
    Goal(id: id, title: 'Goal $id', kind: 'custom', status: 'active', source: 'user', createdAt: 1);

Session sessionFixture([String id = 's']) =>
    Session(id: id, kind: 'activity', type: 'Run', startedAt: 1, endedAt: 2);

/// Lets queued stream events reach their listeners.
Future<void> pump() => Future<void>.delayed(Duration.zero);
