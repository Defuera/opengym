import '../models.dart';
import '../store.dart';
import 'api/open_gym_api.dart';
import 'sync_state_repository.dart';

/// What one sync pass did. Never an exception: failures are reported here.
class SyncResult {
  const SyncResult({this.pushed = 0, this.pulled = 0, this.error});

  final int pushed;
  final int pulled;

  /// Readable reason when the server could not be reached, else null.
  final String? error;

  bool get ok => error == null;
}

/// Keeps finished sessions and the server in step, without ever blocking the
/// UI or throwing. Finished session ids wait in a persisted outbox until the
/// server accepts them (PUT /v1/sessions/:id). Sessions the server has but the
/// phone lacks (imports) are pulled and merged by id.
class SyncService {
  SyncService({
    required OpenGymApi api,
    required SyncStateRepository state,
    required AppStore store,
  })  : _api = api,
        _state = state,
        _store = store;

  final OpenGymApi _api;
  final SyncStateRepository _state;
  final AppStore _store;

  List<String> _outbox = <String>[];
  int _lastPull = 0;
  bool _loaded = false;
  bool _flushing = false;

  List<String> get outbox => List<String>.unmodifiable(_outbox);

  Future<void> _load() async {
    if (_loaded) {
      return;
    }
    try {
      final SyncState s = await _state.load();
      _outbox = List<String>.from(s.outbox);
      _lastPull = s.lastPull;
    } catch (_) {
      // start empty
    }
    _loaded = true;
  }

  Future<void> _save() async {
    try {
      await _state.save(SyncState(outbox: _outbox, lastPull: _lastPull));
    } catch (_) {
      // best effort
    }
  }

  /// Remember a finished session, then try to push it. True when it reached
  /// the server. Offline simply leaves it in the outbox.
  Future<bool> enqueue(String id) async {
    await _load();
    if (!_outbox.contains(id)) {
      _outbox.add(id);
      await _save();
    }
    await flush();
    return !_outbox.contains(id);
  }

  /// Push everything waiting. Stops at the first connectivity failure.
  Future<SyncResult> flush() async {
    await _load();
    if (_flushing) {
      return const SyncResult();
    }
    _flushing = true;
    int pushed = 0;
    String? error;
    try {
      final Set<String> tried = <String>{};
      while (true) {
        final String? id = _next(tried);
        if (id == null) {
          break;
        }
        tried.add(id);
        final Session? s = _store.sessionById(id);
        if (s == null) {
          _outbox.remove(id);
          continue;
        }
        try {
          await _api.putSession(s);
          _outbox.remove(id);
          pushed++;
        } on ApiException catch (e) {
          if (e.rejected) {
            _outbox.remove(id);
          } else {
            error = e.message;
            break;
          }
        }
      }
    } catch (_) {
      error ??= 'Sync stopped unexpectedly.';
    }
    _flushing = false;
    await _save();
    return SyncResult(pushed: pushed, error: error);
  }

  String? _next(Set<String> tried) {
    for (final String id in _outbox) {
      if (!tried.contains(id)) {
        return id;
      }
    }
    return null;
  }

  /// Pull sessions newer than the last pull (or everything with [full]) and
  /// merge them by id. Returns how many were new on this phone.
  Future<SyncResult> pull({bool full = false}) async {
    await _load();
    try {
      final List<Session> remote =
          await _api.listSessions(since: full ? 0 : _lastPull);
      int newest = _lastPull;
      for (final Session s in remote) {
        if (s.when > newest) {
          newest = s.when;
        }
      }
      final int added = _store.mergeRemote(remote);
      if (newest != _lastPull) {
        _lastPull = newest;
        await _save();
      }
      return SyncResult(pulled: added);
    } on ApiException catch (e) {
      return SyncResult(error: e.message);
    } catch (_) {
      return const SyncResult(error: 'Could not read sessions from the server.');
    }
  }

  /// App start, or the connection came back: push, then pull.
  Future<SyncResult> sync({bool full = false}) async {
    final SyncResult pushed = await flush();
    if (!pushed.ok) {
      return pushed;
    }
    final SyncResult pulled = await pull(full: full);
    return SyncResult(
      pushed: pushed.pushed,
      pulled: pulled.pulled,
      error: pulled.error,
    );
  }

  /// An import was undone on the server: drop its sessions here too.
  void forgetImport(String importId) {
    _store.removeImported(importId);
  }
}
