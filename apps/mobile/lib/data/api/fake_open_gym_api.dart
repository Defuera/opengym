import '../../models.dart';
import 'open_gym_api.dart';

/// In-memory server for tests and the gallery. Flip [online] to simulate the
/// network going away: every call then throws [ApiException].
class FakeOpenGymApi implements OpenGymApi {
  bool online = true;
  bool isConfigured = true;

  /// Sessions the "server" holds, keyed by id.
  final Map<String, Session> serverSessions = <String, Session>{};
  final List<String> putIds = <String>[];

  List<Prediction> predictions = <Prediction>[];
  Plan? plan;
  Dashboard? dashboardResult;
  Review? review;
  final List<Goal> goals = <Goal>[];
  final List<Thread> threads = <Thread>[];
  final Map<String, List<Message>> messages = <String, List<Message>>{};
  final List<ImportJob> jobs = <ImportJob>[];

  /// Each poll of an import job advances it by one step until done.
  int importSteps = 2;
  int _polls = 0;
  int _seq = 0;

  String _id(String p) => '$p${++_seq}';

  void _gate() {
    if (!online) {
      throw const ApiException('Cannot reach the server.');
    }
  }

  @override
  void configure(String serverUrl, String token) {
    isConfigured = serverUrl.trim().isNotEmpty;
  }

  @override
  bool get configured => isConfigured;

  @override
  Future<HealthInfo> health() async {
    _gate();
    return const HealthInfo(ok: true, provider: 'mock', aiConfigured: true, version: '1');
  }

  @override
  Future<List<Session>> listSessions({int since = 0}) async {
    _gate();
    final List<Session> out =
        serverSessions.values.where((Session s) => s.when > since).toList();
    out.sort((Session a, Session b) => a.when.compareTo(b.when));
    return out;
  }

  @override
  Future<void> putSession(Session session) async {
    _gate();
    // Round-trip through the contract shape, like a real server would.
    serverSessions[session.id] = Session.fromJson(session.toContractJson());
    putIds.add(session.id);
  }

  @override
  Future<void> deleteSession(String id) async {
    _gate();
    serverSessions.remove(id);
  }

  @override
  Future<Review?> getReview(String sessionId) async {
    _gate();
    return review;
  }

  @override
  Future<List<Prediction>> getStart() async {
    _gate();
    return predictions;
  }

  @override
  Future<Plan> nextPlan(String type) async {
    _gate();
    final Plan? p = plan;
    if (p == null) {
      throw const ApiException('No plan.', statusCode: 404);
    }
    return p;
  }

  @override
  Future<Dashboard> dashboard(int days) async {
    _gate();
    return dashboardResult ??
        Dashboard(days: days, source: 'rules', modules: const <DashboardModule>[]);
  }

  @override
  Future<List<Goal>> listGoals() async {
    _gate();
    return List<Goal>.from(goals);
  }

  @override
  Future<Goal> createGoal({
    required String title,
    required String kind,
    String? exercise,
    double? targetKg,
    int? sessionsPerWeek,
  }) async {
    _gate();
    final Goal g = Goal(
      id: _id('g'),
      title: title,
      kind: kind,
      status: 'active',
      source: 'user',
      createdAt: 0,
      exercise: exercise,
      targetKg: targetKg,
      sessionsPerWeek: sessionsPerWeek,
    );
    goals.add(g);
    return g;
  }

  @override
  Future<Goal> patchGoal(String id, Map<String, dynamic> changes) async {
    _gate();
    final int i = goals.indexWhere((Goal g) => g.id == id);
    if (i < 0) {
      throw const ApiException('Not found.', statusCode: 404);
    }
    final Map<String, dynamic> m = goals[i].toJson()..addAll(changes);
    goals[i] = Goal.fromJson(m);
    return goals[i];
  }

  @override
  Future<void> deleteGoal(String id) async {
    _gate();
    goals.removeWhere((Goal g) => g.id == id);
  }

  @override
  Future<List<ContextItem>> listContext() async {
    _gate();
    return <ContextItem>[];
  }

  @override
  Future<ContextItem> createContext(String text, String topic) async {
    _gate();
    return ContextItem(
      id: _id('c'),
      text: text,
      topic: topic,
      active: true,
      source: 'user',
      createdAt: 0,
    );
  }

  @override
  Future<ContextItem> patchContext(String id, Map<String, dynamic> changes) async {
    _gate();
    throw const ApiException('Not found.', statusCode: 404);
  }

  @override
  Future<void> deleteContext(String id) async {
    _gate();
  }

  @override
  Future<List<Thread>> listThreads() async {
    _gate();
    return List<Thread>.from(threads.reversed);
  }

  @override
  Future<Thread> createThread(String title) async {
    _gate();
    final Thread t = Thread(id: _id('t'), title: title, createdAt: 0, updatedAt: 0);
    threads.add(t);
    messages[t.id] = <Message>[];
    return t;
  }

  @override
  Future<void> deleteThread(String id) async {
    _gate();
    threads.removeWhere((Thread t) => t.id == id);
    messages.remove(id);
  }

  @override
  Future<List<Message>> listMessages(String threadId) async {
    _gate();
    return List<Message>.from(messages[threadId] ?? <Message>[]);
  }

  @override
  Future<SendResult> sendMessage(
    String threadId,
    String text, {
    List<String> fileIds = const <String>[],
  }) async {
    _gate();
    final Message u = Message(
      id: _id('m'),
      threadId: threadId,
      role: 'user',
      text: text,
      createdAt: 0,
      fileIds: fileIds,
    );
    final Message a = Message(
      id: _id('m'),
      threadId: threadId,
      role: 'assistant',
      text: 'Noted.',
      createdAt: 0,
      sources: const <String>['gym log'],
    );
    messages.putIfAbsent(threadId, () => <Message>[]).addAll(<Message>[u, a]);
    return SendResult(userMessage: u, assistantMessage: a);
  }

  @override
  Future<FileMeta> uploadFile(UploadItem item) async {
    _gate();
    return FileMeta(
      id: _id('f'),
      name: item.name,
      mime: 'application/octet-stream',
      size: 0,
      kind: 'other',
      createdAt: 0,
    );
  }

  @override
  Future<List<int>> fileBytes(String id) async {
    _gate();
    return <int>[];
  }

  ImportJob _job(String id, String status, int total, int processed) {
    return ImportJob(
      id: id,
      status: status,
      total: total,
      processed: processed,
      counts: status == 'done' ? const ImportCounts(sessions: 1) : const ImportCounts(),
      notes: const <String>[],
      createdAt: 0,
    );
  }

  @override
  Future<ImportJob> startImport(List<UploadItem> items) async {
    _gate();
    _polls = 0;
    final ImportJob j = _job(_id('i'), 'running', items.length, 0);
    jobs.insert(0, j);
    return j;
  }

  @override
  Future<ImportJob> getImport(String id) async {
    _gate();
    final int i = jobs.indexWhere((ImportJob j) => j.id == id);
    if (i < 0) {
      throw const ApiException('Not found.', statusCode: 404);
    }
    _polls++;
    final ImportJob old = jobs[i];
    jobs[i] = _polls >= importSteps
        ? _job(id, 'done', old.total, old.total)
        : _job(id, 'running', old.total, _polls);
    return jobs[i];
  }

  @override
  Future<List<ImportJob>> listImports() async {
    _gate();
    return List<ImportJob>.from(jobs);
  }

  @override
  Future<void> deleteImport(String id) async {
    _gate();
    jobs.removeWhere((ImportJob j) => j.id == id);
    serverSessions.removeWhere((String k, Session s) => s.importId == id);
  }

  @override
  Future<List<Map<String, dynamic>>> aiFunctions() async {
    _gate();
    return <Map<String, dynamic>>[];
  }
}
