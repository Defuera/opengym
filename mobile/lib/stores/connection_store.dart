import 'package:flutter/foundation.dart';

import '../data/api/open_gym_api.dart';
import '../data/settings_repository.dart';
import '../models.dart';

enum ConnState { unknown, checking, connected, offline }

/// Server settings plus the "connected / offline" state. The app works fully
/// offline; this only decides whether the extra features are tried.
class ConnectionStore extends ChangeNotifier {
  ConnectionStore({required SettingsRepository settings, required OpenGymApi api})
      : _repo = settings,
        _api = api;

  final SettingsRepository _repo;
  final OpenGymApi _api;

  Settings settings = const Settings();
  ConnState state = ConnState.unknown;
  HealthInfo? health;

  /// Readable reason for the last failed check.
  String? error;

  /// Called after a check succeeded (compose uses it to start a sync).
  Future<void> Function()? onConnected;

  bool get connected => state == ConnState.connected;
  bool get checking => state == ConnState.checking;

  /// Load saved settings, point the API at them and check once.
  Future<void> load() async {
    try {
      settings = await _repo.load();
    } catch (_) {
      settings = const Settings();
    }
    _api.configure(settings.serverUrl, settings.token);
    await check();
  }

  Future<void> save(String url, String token) async {
    settings = Settings(serverUrl: url.trim(), token: token.trim());
    try {
      await _repo.save(settings);
    } catch (_) {
      // keep the in-memory value
    }
    _api.configure(settings.serverUrl, settings.token);
    await check();
  }

  /// GET /v1/health. Never throws.
  Future<void> check() async {
    if (settings.isEmpty) {
      health = null;
      error = 'No server set.';
      state = ConnState.offline;
      notifyListeners();
      return;
    }
    state = ConnState.checking;
    notifyListeners();
    try {
      final HealthInfo h = await _api.health();
      health = h;
      error = h.ok ? null : 'The server answered, but is not ready.';
      state = h.ok ? ConnState.connected : ConnState.offline;
      if (h.ok) {
        await _checkToken();
      }
    } on ApiException catch (e) {
      health = null;
      error = e.message;
      state = ConnState.offline;
    } catch (_) {
      health = null;
      error = 'Could not reach the server.';
      state = ConnState.offline;
    }
    notifyListeners();
    final Future<void> Function()? cb = onConnected;
    if (state == ConnState.connected && cb != null) {
      try {
        await cb();
      } catch (_) {
        // sync problems never surface here
      }
    }
  }

  /// /v1/health needs no token, so try one cheap authenticated call too.
  Future<void> _checkToken() async {
    try {
      await _api.listGoals();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        error = e.message;
        state = ConnState.offline;
      }
    } catch (_) {
      // other problems show up where they happen
    }
  }

  /// A call elsewhere failed with no response: show offline until the next check.
  void markOffline() {
    if (state != ConnState.offline) {
      state = ConnState.offline;
      notifyListeners();
    }
  }
}
