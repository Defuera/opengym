import 'dart:async';

import '../models.dart';
import '../store.dart';
import 'convex_client.dart';
import 'outbox.dart';

/// Feeds the live session subscription into the local log. There is no pull:
/// the server pushes every change. Writes go the other way through the
/// [Outbox]; sessions with a write waiting are never overwritten.
class SessionSync {
  SessionSync({
    required ConvexClient client,
    required AppStore store,
    required Outbox outbox,
    this.window = 200,
  })  : _client = client,
        _store = store,
        _outbox = outbox;

  final ConvexClient _client;
  final AppStore _store;
  final Outbox _outbox;
  final int window;

  StreamSubscription<List<Session>>? _sub;

  /// Readable reason the subscription failed, else null.
  String? error;

  void start() {
    _sub ??= _client.watchRecentSessions(limit: window).listen(
      (List<Session> list) {
        error = null;
        // The server pushes again after each outbox write is accepted, so a
        // skipped (pending) session is applied on that next update.
        _store.mergeRemote(list, pending: _outbox.pendingSessionIds);
      },
      onError: (Object e) {
        error = e is ConvexCallException ? e.message : 'Could not read sessions.';
      },
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
