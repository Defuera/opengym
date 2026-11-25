import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../models/json_util.dart';
import 'convex_client.dart';
import 'outbox_ops.dart';
import 'upload_item.dart';

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

/// Where a queued chat message stands.
enum ChatDelivery { sending, notSent }

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
    this.maxFailures = 5,
    this.chatTimeout = const Duration(seconds: 90),
  })  : _repo = repo,
        _client = client,
        _isConnected = isConnected;

  final OutboxRepository _repo;
  final ConvexClient _client;
  final bool Function() _isConnected;
  final Duration sendTimeout;
  final Duration retryAfter;

  /// A chat message may upload files, so it gets longer than other writes.
  final Duration chatTimeout;

  /// Failed sends in a row, with the link up, before a write is parked.
  final int maxFailures;

  List<OutboxOp> _ops = <OutboxOp>[];
  List<OutboxOp> _parked = <OutboxOp>[];
  int _seq = 0;
  bool _loaded = false;
  bool _flushing = false;
  bool _again = false;
  Timer? _retry;
  bool _disposed = false;
  int? _sendingSeq;
  String? _lastError;
  final StreamController<Rejection> _rejections = StreamController<Rejection>.broadcast();

  /// Every write that is not yet on the server, parked ones included, so a
  /// local change is never hidden by a server update.
  List<OutboxOp> get ops => List<OutboxOp>.unmodifiable(<OutboxOp>[..._ops, ..._parked]);

  /// Writes set aside after repeated failures. They are kept, never dropped.
  List<OutboxOp> get parked => List<OutboxOp>.unmodifiable(_parked);
  int get parkedCount => _parked.length;
  int get length => _ops.length;
  bool get isEmpty => _ops.isEmpty;

  /// Why the last pass stopped (wrong token, no answer), else null.
  String? get lastError => _lastError;

  Stream<Rejection> get rejections => _rejections.stream;

  /// Ids of sessions with a write waiting. Server data for these ids must not
  /// replace the local copy.
  Set<String> get pendingSessionIds => <String>{
        for (final OutboxOp o in <OutboxOp>[..._ops, ..._parked])
          if (o.type == OutboxOp.sessionSave ||
              o.type == OutboxOp.sessionRemove ||
              o.type == OutboxOp.sessionSetPlace ||
              o.type == OutboxOp.sessionLogText)
            o.targetId,
      };

  /// Read the saved ops. Call once at start.
  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      final List<OutboxOp> all = await _repo.load();
      _ops = all.where((OutboxOp o) => !o.parked).toList();
      _parked = all.where((OutboxOp o) => o.parked).toList();
    } catch (_) {
      _ops = <OutboxOp>[];
      _parked = <OutboxOp>[];
    }
    for (final OutboxOp o in <OutboxOp>[..._ops, ..._parked]) {
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

  /// An activity logged as one text (ADR-018). It queues the same write the
  /// server takes as `commands/sessions:logText`; the session itself is already
  /// in the local log, so it works offline and is read by the server once sent.
  Future<void> logText(Session s) {
    return _enqueue(OutboxOp.sessionLogText, <String, dynamic>{
      'id': s.id,
      'type': s.type,
      'text': s.note ?? '',
      'at': s.startedAt,
    });
  }

  /// The place of a finished session was changed (null clears it). A newer
  /// change of the same session replaces the old one.
  Future<void> setSessionPlace(String id, String? placeId) {
    return _enqueue(
      OutboxOp.sessionSetPlace,
      <String, dynamic>{'id': id, 'placeId': placeId},
      replaces: (OutboxOp o) => o.type == OutboxOp.sessionSetPlace && o.targetId == id,
    );
  }

  Future<void> removeSession(String id) {
    return _enqueue(
      OutboxOp.sessionRemove,
      <String, dynamic>{'id': id},
      replaces: (OutboxOp o) =>
          (o.type == OutboxOp.sessionSave ||
              o.type == OutboxOp.sessionLogText ||
              o.type == OutboxOp.sessionSetPlace) &&
          o.targetId == id,
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

  /// Create or change a limit. A newer save of the same limit replaces the old.
  Future<void> saveLimit(Limit l) {
    return _enqueue(
      OutboxOp.limitSave,
      <String, dynamic>{'id': l.id, 'limit': l.toWire()},
      replaces: (OutboxOp o) => o.type == OutboxOp.limitSave && o.targetId == l.id,
    );
  }

  Future<void> removeLimit(String limitId) => _enqueue(
        OutboxOp.limitRemove,
        <String, dynamic>{'id': limitId},
        replaces: (OutboxOp o) => o.type == OutboxOp.limitSave && o.targetId == limitId,
      );

  Future<void> addRecord(LimitRecord r) =>
      _enqueue(OutboxOp.recordAdd, <String, dynamic>{'id': r.id, 'record': r.toJson()});

  Future<void> removeRecord(String recordId) => _enqueue(
        OutboxOp.recordRemove,
        <String, dynamic>{'id': recordId},
        replaces: (OutboxOp o) => o.type == OutboxOp.recordAdd && o.targetId == recordId,
      );

  Future<void> saveCheckin(Checkin c) =>
      _enqueue(OutboxOp.checkinSave, <String, dynamic>{'id': c.id, 'checkin': c.toJson()});

  /// A chat message (ADR-037). Saved to disk first; the send runs in the
  /// background, so the caller never waits for the network. [thread] (title,
  /// placeId, about) is set on the first message of a new chat: the op makes
  /// the thread before it sends. The files are kept by path, so they survive a
  /// restart; [items] keeps the picked items for this run.
  Future<void> sendChat({
    required String messageId,
    required String threadId,
    required String text,
    required List<(String, UploadItem)> files,
    ChatContext? context,
    ChatAnswer? answer,
    Map<String, dynamic>? thread,
    int? createdAt,
  }) async {
    for (final (String id, UploadItem item) in files) {
      ChatFiles.items[id] = item;
    }
    await _enqueue(
      OutboxOp.chatSend,
      <String, dynamic>{
        'id': messageId,
        'threadId': threadId,
        'text': text,
        'createdAt': createdAt ?? DateTime.now().millisecondsSinceEpoch,
        'files': <Map<String, dynamic>>[
          for (final (String id, UploadItem item) in files) <String, dynamic>{'id': id, 'path': item.path, 'name': item.name},
        ],
        if (context != null) 'context': context.toJson(),
        if (answer != null) 'answer': answer.toJson(),
        if (thread != null) 'thread': thread,
      },
      flushNow: false,
    );
    unawaited(flush());
  }

  /// The chat messages that wait, parked ones included, oldest first.
  List<QueuedChat> get chats => <QueuedChat>[
        for (final OutboxOp o in <OutboxOp>[..._ops, ..._parked]..sort((OutboxOp a, OutboxOp b) => a.seq.compareTo(b.seq)))
          if (o.chat case final QueuedChat q) q,
      ];

  /// A chat message is being sent right now.
  bool get sendingChat {
    final int? s = _sendingSeq;
    return s != null && _ops.any((OutboxOp o) => o.seq == s && o.type == OutboxOp.chatSend);
  }

  /// Where a queued chat message stands: waiting or going out now
  /// ([ChatDelivery.sending]), or not going out ([ChatDelivery.notSent]: no
  /// link, a failed try, or set aside). Null when it is not in the outbox.
  ChatDelivery? chatDelivery(String messageId) {
    for (final OutboxOp o in <OutboxOp>[..._ops, ..._parked]) {
      if (o.type != OutboxOp.chatSend || o.targetId != messageId) {
        continue;
      }
      if (o.parked || !_isConnected()) {
        return ChatDelivery.notSent;
      }
      return (o.seq == _sendingSeq || o.attempts == 0) ? ChatDelivery.sending : ChatDelivery.notSent;
    }
    return null;
  }

  /// "Try again" on one message: a set-aside one goes back to the queue with
  /// its counter reset; then the queue is sent now.
  Future<void> retryChat(String messageId) async {
    await load();
    final int i = _parked.indexWhere((OutboxOp o) => o.type == OutboxOp.chatSend && o.targetId == messageId);
    if (i >= 0) {
      final OutboxOp op = _parked.removeAt(i).copyWith(failures: 0, parked: false);
      _ops = <OutboxOp>[..._ops, op]..sort((OutboxOp a, OutboxOp b) => a.seq.compareTo(b.seq));
      await _persist();
      notifyListeners();
    }
    _retry?.cancel();
    await flush();
  }

  /// Drops the queued chat messages of a thread (the thread was deleted).
  Future<void> dropChatsOf(String threadId) async {
    await load();
    bool mine(OutboxOp o) => o.type == OutboxOp.chatSend && str(o.args['threadId']) == threadId;
    _ops.removeWhere(mine);
    _parked.removeWhere(mine);
    await _persist();
    notifyListeners();
  }

  Future<void> _enqueue(
    String type,
    Map<String, dynamic> args, {
    bool Function(OutboxOp)? replaces,
    bool flushNow = true,
  }) async {
    await load();
    if (replaces != null) {
      _ops.removeWhere(replaces);
    }
    _ops.add(OutboxOp(seq: ++_seq, type: type, args: args));
    await _persist(); // on disk before anything is sent
    notifyListeners();
    if (flushNow) {
      await flush();
    }
  }

  Future<void> _persist() async {
    try {
      await _repo.save(<OutboxOp>[..._ops, ..._parked]);
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
      _sendingSeq = op.seq;
      notifyListeners();
      try {
        await op.send(_client).timeout(op.type == OutboxOp.chatSend ? chatTimeout : sendTimeout);
      } on ConvexCallException catch (e) {
        _sendingSeq = null;
        if (e.rejected && op.type == OutboxOp.chatSend) {
          // A refused message is never dropped: it stays as "Not sent" with its text.
          _lastError = e.message;
          _ops.removeWhere((OutboxOp o) => o.seq == op.seq);
          _parked.add(op.copyWith(parked: true));
          await _persist();
          notifyListeners();
          continue;
        }
        if (e.rejected) {
          _ops.removeWhere((OutboxOp o) => o.seq == op.seq);
          await _persist();
          _rejections.add(Rejection(op, e.message));
          notifyListeners();
          continue;
        }
        if (await _stop(op, e.message, retry: !e.unauthorized, count: !e.unauthorized)) {
          continue;
        }
        return;
      } on TimeoutException {
        _sendingSeq = null;
        if (await _stop(op, 'The server did not answer in time.', retry: true, count: true)) {
          continue;
        }
        return;
      } catch (_) {
        _sendingSeq = null;
        if (await _stop(op, 'Could not send a change. The app will try again.',
            retry: true, count: true)) {
          continue;
        }
        return;
      }
      _sendingSeq = null;
      _ops.removeWhere((OutboxOp o) => o.seq == op.seq);
      _lastError = null;
      await _persist();
      notifyListeners();
    }
  }

  /// Keeps the write and stops the pass, unless it has now failed [maxFailures]
  /// times in a row with the link up: then it is parked and this returns true
  /// so the pass goes on with the next write. A failure while the link is down
  /// or the token is not accepted is not counted.
  Future<bool> _stop(
    OutboxOp op,
    String message, {
    required bool retry,
    required bool count,
  }) async {
    _lastError = message;
    final OutboxOp next = op.withAttempt(counted: count && _isConnected());
    final bool park = next.failures >= maxFailures;
    final int i = _ops.indexWhere((OutboxOp o) => o.seq == op.seq);
    if (i >= 0) {
      if (park) {
        _ops.removeAt(i);
        _parked.add(next.copyWith(parked: true));
      } else {
        _ops[i] = next;
      }
    }
    await _persist();
    notifyListeners();
    if (park) {
      return true;
    }
    if (retry && !_disposed) {
      _retry?.cancel();
      _retry = Timer(retryAfter, () => unawaited(flush()));
    }
    return false;
  }

  /// Move every parked write back to the queue with its counter reset, in the
  /// order it first arrived, and send.
  Future<void> retryParked() async {
    await load();
    if (_parked.isEmpty) {
      return;
    }
    _ops = <OutboxOp>[
      ..._ops,
      for (final OutboxOp o in _parked) o.copyWith(failures: 0, parked: false),
    ]..sort((OutboxOp a, OutboxOp b) => a.seq.compareTo(b.seq));
    _parked = <OutboxOp>[];
    await _persist();
    notifyListeners();
    await flush();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _rejections.close();
    super.dispose();
  }
}
