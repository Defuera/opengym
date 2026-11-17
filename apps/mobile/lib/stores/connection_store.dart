import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../data/settings_repository.dart';
import '../data/switchable_convex_client.dart';

/// What the user sees about the link to the backend. No state is a spinner
/// that never ends: a wrong token or address ends in a clear state.
enum ConnState {
  /// No address or token yet.
  notConfigured,

  /// The address is not a web address.
  badUrl,

  /// Opening the connection, or checking the token.
  connecting,
  connected,

  /// No answer (wrong address, no network, or the link dropped).
  offline,

  /// The server answered and refused the token.
  unauthorized,
}

/// Settings plus the state of the live link. The app works fully offline;
/// this only says whether the live features are reachable.
class ConnectionStore extends ChangeNotifier {
  ConnectionStore({
    required SettingsRepository settings,
    required SwitchableConvexClient client,
    this.connectTimeout = const Duration(seconds: 10),
  })  : _repo = settings,
        _client = client;

  final SettingsRepository _repo;
  final SwitchableConvexClient _client;
  final Duration connectTimeout;

  Settings settings = const Settings();
  ConnState state = ConnState.notConfigured;

  /// Readable reason for the current state, when there is one.
  String? error;

  /// Called each time the link becomes usable (compose flushes the outbox).
  void Function()? onConnected;

  StreamSubscription<ConvexLink>? _sub;
  Timer? _timer;
  Completer<void>? _settled;
  int _gen = 0;

  bool get connected => state == ConnState.connected;
  bool get checking => state == ConnState.connecting;

  /// True when the old REST server can be used (chat, files, import). It
  /// cannot while the address is a Convex deployment.
  bool get legacyRestReady =>
      settings.serverUrl.trim().isNotEmpty && !isConvexUrl(settings.serverUrl);

  /// Load saved settings and open the link. Never throws.
  Future<void> load() async {
    try {
      settings = await _repo.load();
    } catch (_) {
      settings = const Settings();
    }
    await _apply();
  }

  /// Save new settings, reopen the link and wait for a clear answer.
  Future<void> save(String url, String token) async {
    settings = Settings(serverUrl: url.trim(), token: token.trim());
    try {
      await _repo.save(settings);
    } catch (_) {
      // keep the in-memory value
    }
    await _apply();
    final Completer<void>? wait = _settled;
    if (wait != null) {
      await wait.future.timeout(connectTimeout * 2, onTimeout: () {});
    }
  }

  Future<void> _apply() async {
    final int gen = ++_gen;
    await _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _settled = Completer<void>();
    if (settings.isEmpty || settings.token.isEmpty) {
      await _client.configure('', '');
      _set(ConnState.notConfigured, settings.isEmpty ? 'No server address set.' : 'No token set.');
      return;
    }
    if (!isUsableServerUrl(settings.serverUrl)) {
      await _client.configure('', '');
      _set(ConnState.badUrl,
          'That address is not valid. It looks like https://<name>.convex.cloud.');
      return;
    }
    _set(ConnState.connecting, null);
    await _client.configure(settings.serverUrl, settings.token);
    if (gen != _gen) {
      return;
    }
    _sub = _client.connection.listen((ConvexLink l) => _onLink(gen, l));
    _armTimer(gen);
  }

  void _armTimer(int gen) {
    _timer?.cancel();
    _timer = Timer(connectTimeout, () {
      if (gen == _gen && state == ConnState.connecting) {
        _set(ConnState.offline, 'Could not reach the server. Check the address and your network.');
      }
    });
  }

  void _onLink(int gen, ConvexLink l) {
    if (gen != _gen || state == ConnState.unauthorized && l != ConvexLink.connected) {
      return;
    }
    switch (l) {
      case ConvexLink.notConfigured:
        break;
      case ConvexLink.connecting:
        if (state != ConnState.connected) {
          _set(ConnState.connecting, null);
        }
      case ConvexLink.connected:
        unawaited(_verify(gen));
      case ConvexLink.reconnecting:
        // The socket is trying again. Before the first success that is still
        // "connecting" (the timer ends it); after a drop it is offline.
        if (state == ConnState.connected) {
          _set(ConnState.offline,
              'Connection lost. Trying again. Everything is saved on this phone.');
        }
      case ConvexLink.offline:
        _timer?.cancel();
        _set(ConnState.offline, 'No connection. Everything is saved on this phone.');
    }
  }

  /// The socket is open: one authenticated call tells a wrong token apart.
  Future<void> _verify(int gen) async {
    final AccessStatus a = await _client.checkAccess();
    if (gen != _gen) {
      return;
    }
    _timer?.cancel();
    switch (a) {
      case AccessStatus.ok:
        final bool was = connected;
        _set(ConnState.connected, null);
        if (!was) {
          onConnected?.call();
        }
      case AccessStatus.unauthorized:
        _set(ConnState.unauthorized, const ConvexCallException.unauthorized().message);
      case AccessStatus.notConfigured:
        _set(ConnState.notConfigured, 'No server address set.');
      case AccessStatus.unreachable:
      case AccessStatus.failed:
        _set(ConnState.offline, 'The server did not answer the check.');
    }
  }

  void _set(ConnState s, String? message) {
    state = s;
    error = message;
    if (s != ConnState.connecting) {
      final Completer<void>? c = _settled;
      if (c != null && !c.isCompleted) {
        c.complete();
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
