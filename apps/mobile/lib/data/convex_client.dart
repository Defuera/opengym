import 'dart:async';

import 'package:dartvex/dartvex.dart' as cx;

import '../models.dart';
import 'convex_codec.dart';
import 'convex_types.dart';

export 'convex_types.dart';

/// The app's gateway to the hosted Convex backend: typed live streams and
/// typed commands. The only seam that knows the wire format.
///
/// Streams are LIVE: subscribe once and every change is pushed. A stream emits
/// an error event ([ConvexCallException]) when the server refuses (for
/// example a wrong token) and keeps running. Commands are idempotent on the
/// server (client-made ids), so the outbox may send them again.
abstract class ConvexClient {
  /// Link state changes. The first event is the current state.
  Stream<ConvexLink> get connection;

  // ---------- live reads ----------

  /// Newest first.
  Stream<List<Session>> watchRecentSessions({int limit = 200});

  /// Sessions that ended after [since] (epoch ms), oldest first.
  Stream<List<Session>> watchSessionsSince(int since);
  Stream<List<Goal>> watchGoals();
  Stream<List<ContextItem>> watchContext();
  Stream<Stored<Plan>> watchNextPlan(String type);
  Stream<Stored<List<Prediction>>> watchPredictions();

  /// [days] is 7 or 30.
  Stream<Stored<Dashboard>> watchDashboard(int days);

  /// The value is null while the session is not on the server.
  Stream<Stored<Review?>> watchReview(String sessionId);
  Stream<List<ImportJob>> watchImports();

  // ---------- commands ----------

  Future<void> saveSession(Session session);
  Future<void> removeSession(String sessionId);
  Future<void> createGoal({
    required String goalId,
    required String title,
    required String kind,
    String? exercise,
    double? targetKg,
    int? sessionsPerWeek,
  });
  Future<void> updateGoal(String goalId, GoalPatch patch);
  Future<void> removeGoal(String goalId);
  Future<void> createContext({
    required String itemId,
    required String text,
    required String topic,
  });
  Future<void> updateContext(String itemId, ContextPatch patch);
  Future<void> removeContext(String itemId);
  Future<void> removeImport(String importId);

  /// One authenticated call. Tells a wrong token from an unreachable server.
  Future<AccessStatus> checkAccess();

  Future<void> dispose();
}

/// [ConvexClient] on top of the community `dartvex` package. The only file in
/// the app that imports `dartvex`.
class DartvexConvexClient implements ConvexClient {
  /// Opens a socket to [url] (`https://<name>.convex.cloud`).
  /// [token] is the interim shared app token.
  factory DartvexConvexClient.connect({
    required String url,
    required String token,
  }) {
    final cx.ConvexClient raw = cx.ConvexClient(url);
    return DartvexConvexClient(
      caller: raw,
      token: token,
      connectionStates: raw.connectionStatus.map(_link),
      onDispose: () async => raw.dispose(),
    );
  }

  /// For tests: pass a fake [cx.ConvexFunctionCaller].
  DartvexConvexClient({
    required cx.ConvexFunctionCaller caller,
    required String token,
    required Stream<ConvexLink> connectionStates,
    Future<void> Function()? onDispose,
    this.accessTimeout = const Duration(seconds: 8),
  })  : _caller = caller,
        _token = token,
        _states = connectionStates,
        _onDispose = onDispose;

  final cx.ConvexFunctionCaller _caller;
  final String _token;
  final Stream<ConvexLink> _states;
  final Future<void> Function()? _onDispose;
  final Duration accessTimeout;

  static ConvexLink _link(cx.ConnectionStatus s) {
    if (s.isConnected) {
      return ConvexLink.connected;
    }
    if (!s.hasEverConnected) {
      return ConvexLink.connecting;
    }
    return s.isWebSocketConnected ? ConvexLink.reconnecting : ConvexLink.offline;
  }

  @override
  Stream<ConvexLink> get connection => _states;

  // ---------- live reads ----------

  @override
  Stream<List<Session>> watchRecentSessions({int limit = 200}) =>
      _watch('queries/sessions:recent', <String, dynamic>{'limit': limit}, decodeSessions);

  @override
  Stream<List<Session>> watchSessionsSince(int since) =>
      _watch('queries/sessions:since', <String, dynamic>{'since': since}, decodeSessions);

  @override
  Stream<List<Goal>> watchGoals() =>
      _watch('queries/goals:list', const <String, dynamic>{}, decodeGoals);

  @override
  Stream<List<ContextItem>> watchContext() =>
      _watch('queries/context:list', const <String, dynamic>{}, decodeContext);

  @override
  Stream<Stored<Plan>> watchNextPlan(String type) =>
      _watch('queries/plans:next', <String, dynamic>{'type': type}, decodePlan);

  @override
  Stream<Stored<List<Prediction>>> watchPredictions() =>
      _watch('queries/start:predictions', const <String, dynamic>{}, decodePredictions);

  @override
  Stream<Stored<Dashboard>> watchDashboard(int days) =>
      _watch('queries/dashboard:get', <String, dynamic>{'days': days}, decodeDashboard);

  @override
  Stream<Stored<Review?>> watchReview(String sessionId) =>
      _watch('queries/reviews:get', <String, dynamic>{'sessionId': sessionId}, decodeReview);

  @override
  Stream<List<ImportJob>> watchImports() =>
      _watch('queries/imports:list', const <String, dynamic>{}, decodeImports);

  Stream<T> _watch<T>(
    String name,
    Map<String, dynamic> args,
    T Function(Object?) decode,
  ) {
    late final StreamController<T> out;
    cx.ConvexSubscription? sub;
    StreamSubscription<cx.QueryResult>? listener;
    out = StreamController<T>(
      onListen: () {
        sub = _caller.subscribe(name, <String, dynamic>{'token': _token, ...args});
        listener = sub!.stream.listen((cx.QueryResult r) {
          switch (r) {
            case cx.QuerySuccess(:final Object? value):
              try {
                out.add(decode(value));
              } catch (_) {
                out.addError(const ConvexCallException(
                    'The server sent an answer the app does not understand.'));
              }
            case cx.QueryError(:final Object? data):
              out.addError(ConvexCallException.fromData(data));
            case cx.QueryLoading():
              break;
          }
        });
      },
      onCancel: () async {
        await listener?.cancel();
        sub?.cancel();
      },
    );
    return out.stream;
  }

  // ---------- commands ----------

  @override
  Future<void> saveSession(Session session) =>
      _mutate('commands/sessions:save', <String, dynamic>{'session': encodeSession(session)});

  @override
  Future<void> removeSession(String sessionId) =>
      _mutate('commands/sessions:remove', <String, dynamic>{'sessionId': sessionId});

  @override
  Future<void> createGoal({
    required String goalId,
    required String title,
    required String kind,
    String? exercise,
    double? targetKg,
    int? sessionsPerWeek,
  }) {
    return _mutate('commands/goals:create', <String, dynamic>{
      'goalId': goalId,
      'title': title,
      'kind': kind,
      if (exercise != null) 'exercise': exercise,
      if (targetKg != null) 'targetKg': targetKg,
      if (sessionsPerWeek != null) 'sessionsPerWeek': sessionsPerWeek,
    });
  }

  @override
  Future<void> updateGoal(String goalId, GoalPatch patch) =>
      _mutate('commands/goals:update', <String, dynamic>{'goalId': goalId, ...patch.toJson()});

  @override
  Future<void> removeGoal(String goalId) =>
      _mutate('commands/goals:remove', <String, dynamic>{'goalId': goalId});

  @override
  Future<void> createContext({
    required String itemId,
    required String text,
    required String topic,
  }) {
    return _mutate('commands/context:create',
        <String, dynamic>{'itemId': itemId, 'text': text, 'topic': topic});
  }

  @override
  Future<void> updateContext(String itemId, ContextPatch patch) =>
      _mutate('commands/context:update', <String, dynamic>{'itemId': itemId, ...patch.toJson()});

  @override
  Future<void> removeContext(String itemId) =>
      _mutate('commands/context:remove', <String, dynamic>{'itemId': itemId});

  @override
  Future<void> removeImport(String importId) =>
      _mutate('commands/imports:remove', <String, dynamic>{'importId': importId});

  Future<void> _mutate(String name, Map<String, dynamic> args) async {
    try {
      await _caller.mutate(name, <String, dynamic>{'token': _token, ...args});
    } on cx.ConvexException catch (e) {
      // Never use e.message: it carries a server stack trace.
      throw ConvexCallException.fromData(e.data);
    }
  }

  @override
  Future<AccessStatus> checkAccess() async {
    try {
      await _caller
          .query('queries/goals:list', <String, dynamic>{'token': _token}).timeout(accessTimeout);
      return AccessStatus.ok;
    } on TimeoutException {
      return AccessStatus.unreachable;
    } on cx.ConvexException catch (e) {
      return ConvexCallException.fromData(e.data).unauthorized
          ? AccessStatus.unauthorized
          : AccessStatus.failed;
    } catch (_) {
      return AccessStatus.unreachable;
    }
  }

  @override
  Future<void> dispose() async => _onDispose?.call();
}
