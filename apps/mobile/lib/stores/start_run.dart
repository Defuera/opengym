import 'dart:async';

import '../data/convex_client.dart';
import '../models.dart';
import '../planner.dart';

/// One start request (or, with feedback, a rebuild of an earlier one) (a chosen activity name and an optional note, or a typed text): sends `commands/start:request` with a
/// client-made request id, then watches `queries/start:request`.
///
/// [result] completes with the proposal when the request is ready, and with
/// null on a failed request, a send error, or [budget] running out. It never
/// throws. [cancel] stops watching; [result] then stays unfinished.
///
/// After [budget] ran out the run keeps watching ([gaveUp] is true): an answer
/// that comes later completes [late], so the session screen can offer it.
class StartRun {
  StartRun({
    required ConvexClient client,
    String? name,
    String? text,
    String? feedback,
    String? previousRequestId,
    List<Map<String, dynamic>>? previousPlan,
    required Duration budget,
  }) : requestId = newId() {
    _timer = Timer(budget, _giveUp);
    _start(client, name, text, feedback, previousRequestId, previousPlan);
  }

  final String requestId;
  final Completer<StartProposal?> _done = Completer<StartProposal?>();
  StreamSubscription<StartRequest?>? _sub;
  Timer? _timer;
  final Completer<StartProposal> _late = Completer<StartProposal>();
  bool _cancelled = false;
  bool _gaveUp = false;

  Future<StartProposal?> get result => _done.future;

  /// [budget] ran out before an answer came.
  bool get gaveUp => _gaveUp;

  /// The proposal of an answer that came after [budget] ran out. It stays
  /// unfinished when no such answer comes.
  Future<StartProposal> get late => _late.future;

  Future<void> _start(
    ConvexClient client,
    String? name,
    String? text,
    String? feedback,
    String? previousRequestId,
    List<Map<String, dynamic>>? previousPlan,
  ) async {
    try {
      // Listen first, so an answer cannot be missed.
      _sub = client.watchStartRequest(requestId).listen(
        (StartRequest? r) {
          if (r == null || r.pending) {
            return;
          }
          final StartProposal? p = r.status == 'ready' ? r.proposal : null;
          if (_gaveUp) {
            _sub?.cancel();
            if (p != null && !_cancelled && !_late.isCompleted) {
              _late.complete(p);
            }
            return;
          }
          _finish(p);
        },
        onError: (Object e) => _finish(null),
      );
      await client.requestStart(
        requestId: requestId,
        name: name,
        text: text,
        feedback: feedback,
        previousRequestId: previousRequestId,
        previousPlan: previousPlan,
      );
    } catch (_) {
      _finish(null);
    }
  }

  void _finish(StartProposal? p) {
    if (_cancelled || _done.isCompleted) {
      return;
    }
    _release();
    _done.complete(p);
  }

  /// The budget ran out: [result] is null, and the run keeps watching for [late].
  void _giveUp() {
    if (_cancelled || _done.isCompleted) {
      return;
    }
    _gaveUp = true;
    _done.complete(null);
  }

  void _release() {
    _timer?.cancel();
    _sub?.cancel();
  }

  void cancel() {
    _cancelled = true;
    _release();
  }
}
