import 'dart:async';

import '../data/convex_client.dart';
import '../models.dart';
import '../planner.dart';

/// One typed "something new" request: sends `commands/start:request` with a
/// client-made request id, then watches `queries/start:request`.
///
/// [result] completes with the proposal when the request is ready, and with
/// null on a failed request, a send error, or [budget] running out. It never
/// throws. [cancel] stops watching; [result] then stays unfinished.
class StartRun {
  StartRun({required ConvexClient client, required String text, required Duration budget})
      : requestId = newId() {
    _timer = Timer(budget, () => _finish(null));
    _start(client, text);
  }

  final String requestId;
  final Completer<StartProposal?> _done = Completer<StartProposal?>();
  StreamSubscription<StartRequest?>? _sub;
  Timer? _timer;
  bool _cancelled = false;

  Future<StartProposal?> get result => _done.future;

  Future<void> _start(ConvexClient client, String text) async {
    try {
      // Listen first, so an answer cannot be missed.
      _sub = client.watchStartRequest(requestId).listen(
        (StartRequest? r) {
          if (r == null || r.pending) {
            return;
          }
          _finish(r.status == 'ready' ? r.proposal : null);
        },
        onError: (Object e) => _finish(null),
      );
      await client.requestStart(requestId: requestId, text: text);
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

  void _release() {
    _timer?.cancel();
    _sub?.cancel();
  }

  void cancel() {
    _cancelled = true;
    _release();
  }
}
