import '../../models.dart';
import 'api_transport.dart';
import 'open_gym_api.dart';

/// Real client: one method per endpoint, all HTTP details in [ApiTransport].
/// Timeouts: 4 s default, 12 s for plans, 60 s for chat and uploads.
class HttpOpenGymApi implements OpenGymApi {
  HttpOpenGymApi({ApiTransport? transport}) : _t = transport ?? ApiTransport();

  final ApiTransport _t;

  @override
  void configure(String serverUrl, String token) => _t.configure(serverUrl, token);

  @override
  bool get configured => _t.configured;

  // ---------- health, sessions ----------

  @override
  Future<HealthInfo> health() async {
    return HealthInfo.fromJson(await _t.get('/v1/health'));
  }

  @override
  Future<List<Session>> listSessions({int since = 0}) async {
    final Map<String, dynamic> j = await _t.get('/v1/sessions?since=$since', ApiTransport.longTimeout);
    return parseList<Session>(j['sessions'], Session.fromJson);
  }

  @override
  Future<void> putSession(Session session) async {
    await _t.send('PUT', '/v1/sessions/${Uri.encodeComponent(session.id)}',
        session.toContractJson());
  }

  @override
  Future<void> deleteSession(String id) async {
    await _t.send('DELETE', '/v1/sessions/${Uri.encodeComponent(id)}', null);
  }

  @override
  Future<Review?> getReview(String sessionId) async {
    final Map<String, dynamic> j =
        await _t.get('/v1/sessions/${Uri.encodeComponent(sessionId)}/review');
    final Object? r = j['review'];
    return r is Map ? Review.fromJson(Map<String, dynamic>.from(r)) : null;
  }

  // ---------- start, plans, dashboard ----------

  @override
  Future<List<Prediction>> getStart() async {
    final Map<String, dynamic> j = await _t.get('/v1/start');
    return parseList<Prediction>(j['predictions'], Prediction.fromJson);
  }

  @override
  Future<Plan> nextPlan(String type) async {
    final Map<String, dynamic> j =
        await _t.get('/v1/plans/next?type=${Uri.encodeQueryComponent(type)}', ApiTransport.planTimeout);
    return Plan.fromJson(parseObj(j, 'plan'));
  }

  @override
  Future<Dashboard> dashboard(int days) async {
    final Map<String, dynamic> j = await _t.get('/v1/dashboard?days=$days');
    return Dashboard.fromJson(parseObj(j, 'dashboard'));
  }

  // ---------- goals ----------

  @override
  Future<List<Goal>> listGoals() async {
    final Map<String, dynamic> j = await _t.get('/v1/goals');
    return parseList<Goal>(j['goals'], Goal.fromJson);
  }

  @override
  Future<Goal> createGoal({
    required String title,
    required String kind,
    String? exercise,
    double? targetKg,
    int? sessionsPerWeek,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{'title': title, 'kind': kind};
    if (exercise != null && exercise.isNotEmpty) {
      body['exercise'] = exercise;
    }
    if (targetKg != null) {
      body['targetKg'] = targetKg;
    }
    if (sessionsPerWeek != null) {
      body['sessionsPerWeek'] = sessionsPerWeek;
    }
    final Map<String, dynamic> j = await _t.send('POST', '/v1/goals', body);
    return Goal.fromJson(parseObj(j, 'goal'));
  }

  @override
  Future<Goal> patchGoal(String id, Map<String, dynamic> changes) async {
    final Map<String, dynamic> j =
        await _t.send('PATCH', '/v1/goals/${Uri.encodeComponent(id)}', changes);
    return Goal.fromJson(parseObj(j, 'goal'));
  }

  @override
  Future<void> deleteGoal(String id) async {
    await _t.send('DELETE', '/v1/goals/${Uri.encodeComponent(id)}', null);
  }

  // ---------- context ----------

  @override
  Future<List<ContextItem>> listContext() async {
    final Map<String, dynamic> j = await _t.get('/v1/context');
    return parseList<ContextItem>(j['items'], ContextItem.fromJson);
  }

  @override
  Future<ContextItem> createContext(String text, String topic) async {
    final Map<String, dynamic> j = await _t.send(
        'POST', '/v1/context', <String, dynamic>{'text': text, 'topic': topic});
    return ContextItem.fromJson(parseObj(j, 'item'));
  }

  @override
  Future<ContextItem> patchContext(String id, Map<String, dynamic> changes) async {
    final Map<String, dynamic> j =
        await _t.send('PATCH', '/v1/context/${Uri.encodeComponent(id)}', changes);
    return ContextItem.fromJson(parseObj(j, 'item'));
  }

  @override
  Future<void> deleteContext(String id) async {
    await _t.send('DELETE', '/v1/context/${Uri.encodeComponent(id)}', null);
  }

  // ---------- threads ----------

  @override
  Future<List<Thread>> listThreads() async {
    final Map<String, dynamic> j = await _t.get('/v1/threads');
    return parseList<Thread>(j['threads'], Thread.fromJson);
  }

  @override
  Future<Thread> createThread(String title) async {
    final Map<String, dynamic> j =
        await _t.send('POST', '/v1/threads', <String, dynamic>{'title': title});
    return Thread.fromJson(parseObj(j, 'thread'));
  }

  @override
  Future<void> deleteThread(String id) async {
    await _t.send('DELETE', '/v1/threads/${Uri.encodeComponent(id)}', null);
  }

  @override
  Future<List<Message>> listMessages(String threadId) async {
    final Map<String, dynamic> j =
        await _t.get('/v1/threads/${Uri.encodeComponent(threadId)}/messages');
    return parseList<Message>(j['messages'], Message.fromJson);
  }

  @override
  Future<SendResult> sendMessage(
    String threadId,
    String text, {
    List<String> fileIds = const <String>[],
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{'text': text};
    if (fileIds.isNotEmpty) {
      body['fileIds'] = fileIds;
    }
    final Map<String, dynamic> j = await _t.send(
      'POST',
      '/v1/threads/${Uri.encodeComponent(threadId)}/messages',
      body,
      ApiTransport.longTimeout,
    );
    return SendResult.fromJson(j);
  }

  // ---------- files and import ----------

  @override
  Future<FileMeta> uploadFile(UploadItem item) async {
    final Map<String, dynamic> j =
        await _t.upload('/v1/files', 'file', <UploadItem>[item]);
    return FileMeta.fromJson(parseObj(j, 'file'));
  }

  @override
  Future<List<int>> fileBytes(String id) async {
    return _t.bytes('/v1/files/${Uri.encodeComponent(id)}');
  }

  @override
  Future<ImportJob> startImport(List<UploadItem> items) async {
    final Map<String, dynamic> j = await _t.upload('/v1/import', 'files', items);
    return ImportJob.fromJson(parseObj(j, 'job'));
  }

  @override
  Future<ImportJob> getImport(String id) async {
    final Map<String, dynamic> j =
        await _t.get('/v1/import/${Uri.encodeComponent(id)}');
    return ImportJob.fromJson(parseObj(j, 'job'));
  }

  @override
  Future<List<ImportJob>> listImports() async {
    final Map<String, dynamic> j = await _t.get('/v1/import');
    return parseList<ImportJob>(j['jobs'], ImportJob.fromJson);
  }

  @override
  Future<void> deleteImport(String id) async {
    await _t.send('DELETE', '/v1/import/${Uri.encodeComponent(id)}', null);
  }

  @override
  Future<List<Map<String, dynamic>>> aiFunctions() async {
    final Map<String, dynamic> j = await _t.get('/v1/ai/functions');
    return parseList<Map<String, dynamic>>(j['functions'], (Map<String, dynamic> m) => m);
  }
}
