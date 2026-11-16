import 'package:flutter/foundation.dart';

import '../data/api/open_gym_api.dart';
import '../models.dart';

/// Waits (politely) for the review of a just-finished session.
class ReviewStore extends ChangeNotifier {
  ReviewStore({
    required OpenGymApi api,
    this.attempts = 6,
    this.every = const Duration(seconds: 3),
  }) : _api = api;

  final OpenGymApi _api;
  final int attempts;
  final Duration every;

  Review? current;

  /// Called when a review arrived (compose refreshes the dashboard).
  void Function()? onArrived;

  String? _watching;

  /// Poll GET /v1/sessions/:id/review a few times. Never throws.
  Future<void> watch(String sessionId) async {
    _watching = sessionId;
    for (int i = 0; i < attempts; i++) {
      await Future<void>.delayed(every);
      if (_watching != sessionId) {
        return;
      }
      try {
        final Review? r = await _api.getReview(sessionId);
        if (r != null) {
          current = r;
          notifyListeners();
          final void Function()? cb = onArrived;
          if (cb != null) {
            cb();
          }
          return;
        }
      } catch (_) {
        // try again on the next round
      }
    }
  }

  void dismiss() {
    _watching = null;
    if (current != null) {
      current = null;
      notifyListeners();
    }
  }
}
