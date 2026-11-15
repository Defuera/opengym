import '../../models.dart';

/// The one error the API layer throws. [message] is safe to show to the user.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;

  /// HTTP status, or null when there was no response (offline, timeout).
  final int? statusCode;

  /// True when the request itself was refused (not a connectivity problem and
  /// not an auth problem), so retrying the same body is pointless.
  bool get rejected {
    final int? c = statusCode;
    return c != null && c >= 400 && c < 500 && c != 401 && c != 408 && c != 429;
  }

  @override
  String toString() => message;
}

/// A local file to upload.
class UploadItem {
  const UploadItem({required this.path, required this.name});

  final String path;
  final String name;
}

/// One method per endpoint in docs/api-contract.md. Every method either
/// returns or throws [ApiException].
abstract class OpenGymApi {
  /// Point the client at a server. Empty URL means "not configured".
  void configure(String serverUrl, String token);

  bool get configured;

  Future<HealthInfo> health();

  // sessions
  Future<List<Session>> listSessions({int since = 0});
  Future<void> putSession(Session session);
  Future<void> deleteSession(String id);
  Future<Review?> getReview(String sessionId);

  // start, plans, dashboard
  Future<List<Prediction>> getStart();
  Future<Plan> nextPlan(String type);
  Future<Dashboard> dashboard(int days);

  // goals
  Future<List<Goal>> listGoals();
  Future<Goal> createGoal({
    required String title,
    required String kind,
    String? exercise,
    double? targetKg,
    int? sessionsPerWeek,
  });
  Future<Goal> patchGoal(String id, Map<String, dynamic> changes);
  Future<void> deleteGoal(String id);

  // context
  Future<List<ContextItem>> listContext();
  Future<ContextItem> createContext(String text, String topic);
  Future<ContextItem> patchContext(String id, Map<String, dynamic> changes);
  Future<void> deleteContext(String id);

  // threads
  Future<List<Thread>> listThreads();
  Future<Thread> createThread(String title);
  Future<void> deleteThread(String id);
  Future<List<Message>> listMessages(String threadId);
  Future<SendResult> sendMessage(
    String threadId,
    String text, {
    List<String> fileIds = const <String>[],
  });

  // files and import
  Future<FileMeta> uploadFile(UploadItem item);
  Future<List<int>> fileBytes(String id);
  Future<ImportJob> startImport(List<UploadItem> items);
  Future<ImportJob> getImport(String id);
  Future<List<ImportJob>> listImports();
  Future<void> deleteImport(String id);

  Future<List<Map<String, dynamic>>> aiFunctions();
}
