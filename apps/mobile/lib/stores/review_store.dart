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
  StreamSubscription<Stored<Review?>>? _sub;

  /// Follow the review of [sessionId]. It appears once the session is on the
  /// server (right away when online, after the outbox sends it otherwise).
  void watch(String sessionId) {
    _sub?.cancel();
    current = null;
    _sub = _client.watchReview(sessionId).listen(
      (Stored<Review?> r) {
        final Review? v = r.value;
        if (v != null) {
          current = v;
          notifyListeners();
        }
      },
      onError: (Object _) {
        // the review is a bonus: no error state
      },
    );
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
