import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../models.dart';

/// The review of a just-finished session, as a live subscription. The rules
/// review shows at once; the AI one replaces it when it is built.
class ReviewStore extends ChangeNotifier {
  ReviewStore({required ConvexClient client}) : _client = client;

  final ConvexClient _client;

  Review? current;

  /// No review yet, but one is expected: the session just ended and the coach
  /// is still writing (ADR-041). The recap shows a quiet line for it.
  bool pending = false;

  /// The last try to open the debrief chat failed (offline).
  bool openFailed = false;
  StreamSubscription<Stored<Review?>>? _sub;

  /// Follow the review of [sessionId]. It appears once the session is on the
  /// server (right away when online, after the outbox sends it otherwise).
  void watch(String sessionId) {
    _sub?.cancel();
    current = null;
    pending = false;
    _sub = _client.watchReview(sessionId).listen(
      (Stored<Review?> r) {
        final Review? v = r.value;
        if (v != null) {
          current = v;
          pending = false;
          notifyListeners();
        } else if (current != null || pending != r.pending) {
          // the session was deleted on the server (its review goes too), or the coach is still writing
          current = null;
          pending = r.pending;
          notifyListeners();
        }
      },
      onError: (Object _) {
        // the review is a bonus: no error state
      },
    );
  }

  /// Opens the debrief chat of [sessionId] on the server (the same thread every
  /// time) and returns its id, or null when that did not work (offline).
  Future<String?> openChat(String sessionId) async {
    openFailed = false;
    try {
      return await _client.openDebrief(sessionId);
    } on Object {
      openFailed = true;
      notifyListeners();
      return null;
    }
  }

  void dismiss() {
    _sub?.cancel();
    _sub = null;
    if (current != null) {
      current = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
