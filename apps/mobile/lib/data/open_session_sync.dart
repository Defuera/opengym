import 'dart:async';
import 'dart:convert';

import '../models.dart';
import '../store.dart';
import 'convex_client.dart';

/// Keeps the open session the same on the phone and on the server (ADR-028).
///
/// The phone saves first; this sync sends the change after, so a tap never
/// waits for the network. Offline, the change stays marked on disk
/// ([AppStore.activeDirty]) and goes out when the connection is back.
///
/// The server's copy is taken only when the phone holds no unsent change and
/// the server's revision is newer than the one the phone has: that is a change
/// made outside the phone (the coach, another device). The phone's own change
/// always wins over an outside one made at the same time.
class OpenSessionSync {
  OpenSessionSync({
    required ConvexClient client,
    required AppStore store,
    required bool Function() isConnected,
    this.delay = const Duration(milliseconds: 400),
  })  : _client = client,
        _store = store,
        _isConnected = isConnected;

  final ConvexClient _client;
  final AppStore _store;
  final bool Function() _isConnected;

  /// Quick taps (plus, plus, plus) go out as one write.
  final Duration delay;

  StreamSubscription<OpenRemote>? _sub;
  Timer? _timer;
  bool _sending = false;
  bool _again = false;

  void start() {
    _store.onActiveChanged = schedule;
    _sub ??= _client.watchOpenSession().listen(_onRemote, onError: (Object _) {});
    schedule();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
  }

  /// Sends what is not sent yet, after [delay].
  void schedule() {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(flush()));
  }

  /// Sends what is not sent yet, now. Never throws: a failure stays marked and
  /// the next change or the next connection tries again.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_sending) {
      _again = true;
      return;
    }
    if (!_isConnected()) {
      return;
    }
    _sending = true;
    try {
      final String? gone = _store.pendingClear;
      if (gone != null) {
        await _client.clearOpenSession(gone);
        _store.markCleared(gone);
      }
      final Session? a = _store.active;
      final String? json = _store.openSessionJson;
      if (a != null && json != null && _store.activeDirty && a.kind == 'gym') {
        final int rev = await _client.putOpenSession(jsonDecode(json) as Map<String, dynamic>);
        _store.markActiveSynced(json, rev);
        if (_store.activeDirty) {
          _again = true;
        }
      }
    } catch (_) {
      // Stays marked as not sent.
    } finally {
      _sending = false;
    }
    if (_again) {
      _again = false;
      schedule();
    }
  }

  void _onRemote(OpenRemote r) {
    final Session? remote = r.session;
    final Session? local = _store.active;
    if (remote == null) {
      // The server holds none: the phone's open session goes there (again).
      if (local != null) {
        _store.markActiveUnsent();
        schedule();
      }
      return;
    }
    if (_store.pendingClear == remote.id) {
      return; // ended on the phone; the clear is on its way
    }
    if (local == null) {
      // Opened elsewhere, or the phone lost it. A session already in the log is not opened again.
      if (remote.kind == 'gym' && _store.sessionById(remote.id) == null) {
        _store.applyRemoteActive(remote, r.rev);
      }
      return;
    }
    if (_store.activeDirty || r.rev <= _store.activeRev) {
      return; // the phone's change wins, or this is the echo of its own write
    }
    final String theirs = jsonEncode(openSessionWire(remote));
    if (local.id == remote.id && theirs == _store.openSessionJson) {
      _store.markActiveSynced(theirs, r.rev);
      return;
    }
    _store.applyRemoteActive(remote, r.rev);
  }
}
