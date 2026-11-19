import 'package:flutter/foundation.dart';

import '../models.dart';
import 'plan_store.dart';
import 'start_run.dart';

/// The feedback loop on a proposed session: the person reads the proposal,
/// types what to change, and the coach rebuilds it. One request at a time.
/// Each rebuild points at the request of the proposal now shown, so the
/// server keeps the chain of feedback.
class ProposalRebuild extends ChangeNotifier {
  ProposalRebuild({
    required PlanStore plans,
    String? requestId,
    required this.activity,
    required this.onProposal,
  })  : _plans = plans,
        _requestId = requestId;

  /// The activity of the shown session. Without a known request (the app was
  /// restarted, or the session did not come from the coach) the feedback goes
  /// as the note of a new request for this activity.
  final String Function() activity;

  final PlanStore _plans;

  /// Shows a new proposal. Returns false when it could not be shown (for
  /// example the session was already started): the rebuild then counts as failed.
  final bool Function(StartProposal) onProposal;

  String? _requestId;
  StartRun? _run;
  bool _failed = false;
  bool _disposed = false;

  bool get busy => _run != null;

  /// The last rebuild failed; the old proposal is still shown.
  bool get failed => _failed;

  /// Sends [feedback] (the caller trims it and checks it is not empty).
  Future<void> rebuild(String feedback) async {
    if (_run != null) {
      return;
    }
    final String? prev = _requestId;
    final StartRun run = prev != null
        ? _plans.requestRebuild(feedback: feedback, previousRequestId: prev)
        : _plans.requestStart(name: activity(), text: feedback.length > 2000 ? feedback.substring(0, 2000) : feedback);
    _run = run;
    _failed = false;
    notifyListeners();
    final StartProposal? p = await run.result;
    if (_disposed || _run != run) {
      return;
    }
    _run = null;
    if (p != null && p.kind == 'gym' && onProposal(p)) {
      _requestId = run.requestId;
    } else {
      _failed = true;
    }
    notifyListeners();
  }

  /// Gives up waiting and keeps the shown proposal.
  void cancel() {
    _run?.cancel();
    _run = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _run?.cancel();
    super.dispose();
  }
}
