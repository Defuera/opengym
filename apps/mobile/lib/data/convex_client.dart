import 'dart:async';

import 'package:dartvex/dartvex.dart' as cx;

import '../models.dart';

/// Coarse link state to the hosted backend.
enum ConvexLink { connecting, connected, reconnecting, offline }

/// Raised when the backend refuses or fails a call.
class ConvexCallException implements Exception {
  const ConvexCallException(this.message);

  final String message;

  @override
  String toString() => 'ConvexCallException: $message';
}

/// Live access to sessions on the hosted Convex backend.
///
/// An interface, so the transport can change and tests can fake it.
abstract class ConvexClient {
  /// Newest first. Emits the current list, then again after every change on
  /// the server. Emits an error event when the call fails (for example a wrong
  /// token).
  Stream<List<Session>> watchRecentSessions({int limit = 20});

  /// Idempotent write, keyed by the session id.
  Future<void> saveSession(Session session);

  /// Link state changes (the first event is the current state).
  Stream<ConvexLink> get connection;

  Future<void> dispose();
}

/// [ConvexClient] on top of the community `dartvex` package.
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
  })  : _caller = caller,
        _token = token,
        _states = connectionStates,
        _onDispose = onDispose;

  final cx.ConvexFunctionCaller _caller;
  final String _token;
  final Stream<ConvexLink> _states;
  final Future<void> Function()? _onDispose;

  static const String _recent = 'queries/sessions:recent';
  static const String _save = 'commands/sessions:save';

  static ConvexLink _link(cx.ConnectionStatus s) {
    if (s.isConnected) {
      return ConvexLink.connected;
    }
    if (!s.hasEverConnected) {
      return ConvexLink.connecting;
    }
    return s.isWebSocketConnected
        ? ConvexLink.reconnecting
        : ConvexLink.offline;
  }

  @override
  Stream<ConvexLink> get connection => _states;

  @override
  Stream<List<Session>> watchRecentSessions({int limit = 20}) {
    late final StreamController<List<Session>> out;
    cx.ConvexSubscription? sub;
    StreamSubscription<cx.QueryResult>? listener;
    out = StreamController<List<Session>>(
      onListen: () {
        sub = _caller.subscribe(
          _recent,
          <String, dynamic>{'token': _token, 'limit': limit},
        );
        listener = sub!.stream.listen((cx.QueryResult r) {
          switch (r) {
            case cx.QuerySuccess(:final Object? value):
              out.add(_decode(value));
            case cx.QueryError(:final String message):
              out.addError(ConvexCallException(message));
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

  @override
  Future<void> saveSession(Session session) async {
    try {
      await _caller.mutate(_save, <String, dynamic>{
        'token': _token,
        'session': _encode(session),
      });
    } on cx.ConvexException catch (e) {
      throw ConvexCallException(e.message);
    }
  }

  @override
  Future<void> dispose() async => _onDispose?.call();

  static Map<String, dynamic> _encode(Session s) {
    final Map<String, dynamic> m = s.toContractJson();
    m['sessionId'] = m.remove('id');
    return m;
  }

  static List<Session> _decode(Object? value) {
    final List<Session> out = <Session>[];
    for (final Object? e in (value as List<dynamic>)) {
      final Map<String, dynamic> m = Map<String, dynamic>.from(e as Map);
      m['id'] = m['sessionId'];
      out.add(Session.fromJson(m));
    }
    return out;
  }
}
