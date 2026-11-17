import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'convex_client.dart';
import 'outbox_ops.dart';

/// Where the outbox keeps its ops between runs.
abstract class OutboxRepository {
  Future<List<OutboxOp>> load();
  Future<void> save(List<OutboxOp> ops);
}

class SharedPrefsOutboxRepository implements OutboxRepository {
  static const String _key = 'opengym-outbox-v2';

  @override
  Future<List<OutboxOp>> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(_key);
    if (raw == null) {
      return <OutboxOp>[];
    }
    try {
      return <OutboxOp>[
        for (final Object? e in jsonDecode(raw) as List<dynamic>)
          if (OutboxOp.tryParse(e) case final OutboxOp op) op,
      ];
    } catch (_) {
      return <OutboxOp>[];
    }
  }

  @override
  Future<void> save(List<OutboxOp> ops) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(ops.map((OutboxOp o) => o.toJson()).toList()));
  }
}

class InMemoryOutboxRepository implements OutboxRepository {
  List<String> stored = <String>[];

  @override
  Future<List<OutboxOp>> load() async => <OutboxOp>[
        for (final String s in stored) OutboxOp.tryParse(jsonDecode(s))!,
      ];

  @override
  Future<void> save(List<OutboxOp> ops) async {
    stored = ops.map((OutboxOp o) => jsonEncode(o.toJson())).toList();
  }
}

/// A write the server refused for good. It was dropped from the outbox.
class Rejection {
  const Rejection(this.op, this.message);

  final OutboxOp op;
  final String message;
}

/// Persistent queue of writes (ADR-003, ADR-012).
///
/// Every write is saved to disk first, then sent in order through the
/// idempotent Convex commands once the link is up. It survives a restart and
/// is retried on reconnect. Logging a set never waits for it.
///
/// Failure rules: a refusal with a reason drops that write and reports a
/// [Rejection]; a wrong token or no answer keeps it and stops the pass.
class Outbox extends ChangeNotifier {
  Outbox({
    required OutboxRepository repo,
    required ConvexClient client,
    required bool Function() isConnected,
    this.sendTimeout = const Duration(seconds: 20),
    this.retryAfter = const Duration(seconds: 10),
  })  : _repo = repo,
        _client = client,
        _isConnected = isConnected;

  final OutboxRepository _repo;
  final ConvexClient _client;
  final bool Function() _isConnected;
  final Duration sendTimeout;
  final Duration retryAfter;

  List<OutboxOp> _ops = <OutboxOp>[];
  int _seq = 0;
  bool _loaded = false;
  bool _flushing = false;
  bool _again = false;
  Timer? _retry;
  bool _disposed = false;
  String? _lastError;
  final StreamController<Rejection> _rejections = StreamController<Rejection>.broadcast();

  List<OutboxOp> get ops => List<OutboxOp>.unmodifiable(_ops);
  int get length => _ops.length;
  bool get isEmpty => _ops.isEmpty;

  /// Why the last pass stopped (wrong token, no answer), else null.
  String? get lastError => _lastError;

  Stream<Rejection> get rejections => _rejections.stream;

  /// Ids of sessions with a write waiting. Server data for these ids must not
  /// replace the local copy.
  Set<String> get pendingSessionIds => <String>{
        for (final OutboxOp o in _ops)
          if (o.type == OutboxOp.sessionSave || o.type == OutboxOp.sessionRemove) o.targetId,
      };

  /// Read the saved ops. Call once at start.
  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      _ops = await _repo.load();
    } catch (_) {
      _ops = <OutboxOp>[];
    }
    for (final OutboxOp o in _ops) {
      if (o.seq > _seq) {
        _seq = o.seq;
      }
    }
    _loaded = true;
    notifyListeners();
  }

  // ---------- writes ----------

  /// A finished session. A newer save of the same session replaces the old one.
  Future<void> saveSession(Session s) {
    return _enqueue(
      OutboxOp.sessionSave,
      <String, dynamic>{'id': s.id, 'session': s.toJson()},
      replaces: (OutboxOp o) => o.type == OutboxOp.sessionSave && o.targetId == s.id,
    );
  }

  Future<void> removeSession(String id) {
    return _enqueue(
      OutboxOp.sessionRemove,
      <String, dynamic>{'id': id},
      replaces: (OutboxOp o) => o.type == OutboxOp.sessionSave && o.targetId == id,
    );
  }

  Future<void> createGoal({
    required String goalId,
    required String title,
    required String kind,
    String? exercise,
    double? targetKg,
    int? sessionsPerWeek,
  }) {
    return _enqueue(OutboxOp.goalCreate, <String, dynamic>{
      'id': goalId,
      'title': title,
      'kind': kind,
      if (exercise != null) 'exercise': exercise,
      if (targetKg != null) 'targetKg': targetKg,
      if (sessionsPerWeek != null) 'sessionsPerWeek': sessionsPerWeek,
      // Local only: keeps the order of the list stable until the server answers.
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updateGoal(String goalId, GoalPatch patch) =>
      _enqueue(OutboxOp.goalUpdate, <String, dynamic>{'id': goalId, 'patch': patch.toJson()});

  Future<void> removeGoal(String goalId) =>
      _enqueue(OutboxOp.goalRemove, <String, dynamic>{'id': goalId});

  Future<void> createContext({
    required String itemId,
    required String text,
    required String topic,
  }) {
    return _enqueue(OutboxOp.contextCreate, <String, dynamic>{
      'id': itemId,
      'text': text,
      'topic': topic,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updateContext(String itemId, ContextPatch patch) =>
      _enqueue(OutboxOp.contextUpdate, <String, dynamic>{'id': itemId, 'patch': patch.toJson()});

  Future<void> removeContext(String itemId) =>
      _enqueue(OutboxOp.contextRemove, <String, dynamic>{'id': itemId});

  Future<void> _enqueue(
    String type,
    Map<String, dynamic> args, {
    bool Function(OutboxOp)? replaces,
  }) async {
    await load();
    if (replaces != null) {
      _ops.removeWhere(replaces);
    }
    _ops.add(OutboxOp(seq: ++_seq, type: type, args: args));
    await _persist(); // on disk before anything is sent
    notifyListeners();
    await flush();
  }

  Future<void> _persist() async {
    try {
      await _repo.save(_ops);
    } catch (_) {
      // The op stays in memory; the next change saves again.
    }
  }

  // ---------- sending ----------

  /// Send what is waiting, in order. Safe to call at any time (on enqueue, on
  /// reconnect, from the retry timer). Never throws.
  Future<void> flush() async {
    await load();
    if (_flushing) {
      _again = true;
      return;
    }
    _flushing = true;
    try {
      do {
        _again = false;
        await _drain();
      } while (_again && !_disposed);
    } finally {
      _flushing = false;
    }
  }

  Future<void> _drain() async {
    while (_ops.isNotEmpty && _isConnected() && !_disposed) {
      final OutboxOp op = _ops.first;
      try {
        await op.send(_client).timeout(sendTimeout);
      } on ConvexCallException catch (e) {
        if (e.rejected) {
          _ops.removeWhere((OutboxOp o) => o.seq == op.seq);
          await _persist();
          _rejections.add(Rejection(op, e.message));
          notifyListeners();
          continue;
        }
        await _stop(op, e.message, retry: !e.unauthorized);
        return;
      } on TimeoutException {
        await _stop(op, 'The server did not answer in time.', retry: true);
        return;
      } catch (_) {
        await _stop(op, 'Could not send a change. The app will try again.', retry: true);
        return;
      }
      _ops.removeWhere((OutboxOp o) => o.seq == op.seq);
      _lastError = null;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> _stop(OutboxOp op, String message, {required bool retry}) async {
    _lastError = message;
    final int i = _ops.indexWhere((OutboxOp o) => o.seq == op.seq);
    if (i >= 0) {
      _ops[i] = op.withAttempt();
    }
    await _persist();
    notifyListeners();
    if (retry && !_disposed) {
      _retry?.cancel();
      _retry = Timer(retryAfter, () => unawaited(flush()));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _rejections.close();
    super.dispose();
  }
}
