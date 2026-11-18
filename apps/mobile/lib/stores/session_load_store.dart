import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';

/// What one finished session loaded, as a live subscription: muscle key ->
/// level 0..3. Null until the server answers (offline: it stays null and the
/// recap shows no figure). It is a bonus, so a failure sets no error state.
class SessionLoadStore extends ChangeNotifier {
  SessionLoadStore({required ConvexClient client}) : _client = client;

  final ConvexClient _client;
  Map<String, int>? load;
  StreamSubscription<Map<String, int>?>? _sub;

  /// Follow the load of [sessionId].
  void watch(String sessionId) {
    _sub?.cancel();
    load = null;
    _sub = _client.watchSessionLoad(sessionId).listen(
      (Map<String, int>? v) {
        load = v;
        notifyListeners();
      },
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
