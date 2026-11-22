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
    this.exercises,
    this.note,
    String? notice,
    StartRun? late,
  })  : _plans = plans,
        _requestId = requestId,
        _notice = notice,
        _late = late {
    late?.late.then((StartProposal p) {
      if (_disposed || _late != late || p.kind != 'gym') {
        return;
      }
      _offer = p;
      notifyListeners();
    });
  }

  /// The note for today the person gave at the start. It goes with feedback on
  /// a session that has no request, so the coach still knows it.
  final String? note;

  /// The activity of the shown session. Without a known request (the app was
  /// restarted, or the session did not come from the coach) the feedback goes
  /// as the note of a new request for this activity.
  final String Function() activity;

  /// The exercises of the shown session. Without a request id they go to the
  /// coach as the plan to change (`previousPlan`). Null or empty: the feedback
  /// is the note of a new request.
  final List<Exercise> Function()? exercises;

  final PlanStore _plans;

  /// Shows a new proposal. Returns false when it could not be shown (for
  /// example the session was already started): the rebuild then counts as failed.
  final bool Function(StartProposal) onProposal;

  String? _requestId;
  String? _notice;
  StartRun? _late;
  StartProposal? _offer;
  StartRun? _run;
  bool _failed = false;
  bool _disposed = false;

  bool get busy => _run != null;

  /// The last rebuild failed; the old proposal is still shown.
  bool get failed => _failed;

  /// Why the shown session is not the coach's plan (the coach did not answer);
  /// null when it is, or after the coach's plan was taken.
  String? get notice => _notice;

  /// The coach's plan that came after the app gave up waiting. Null when there is none.
  StartProposal? get offer => _offer;

  /// Shows the late plan of the coach in place of the session. False when it could not be shown.
  bool useOffer() {
    final StartProposal? p = _offer;
    final StartRun? run = _late;
    if (p == null || run == null) {
      return false;
    }
    _offer = null;
    _late = null;
    final bool shown = onProposal(p);
    if (shown) {
      _requestId = run.requestId;
      _notice = null;
    }
    notifyListeners();
    return shown;
  }

  /// Sends [feedback] (the caller trims it and checks it is not empty).
  Future<void> rebuild(String feedback) async {
    if (_run != null) {
      return;
    }
    // New feedback replaces a late answer to the first request.
    _late?.cancel();
    _late = null;
    _offer = null;
    final String? prev = _requestId;
    final List<Map<String, dynamic>> plan = compactPlan(exercises?.call() ?? <Exercise>[]);
    final StartRun run;
    if (prev != null) {
      run = _plans.requestRebuild(feedback: feedback, previousRequestId: prev);
    } else if (plan.isNotEmpty) {
      run = _plans.requestFeedbackOnPlan(name: activity(), feedback: feedback, previousPlan: plan, note: note);
    } else {
      run = _plans.requestStart(name: activity(), text: feedback.length > 2000 ? feedback.substring(0, 2000) : feedback);
    }
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
      _notice = null;
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
    _late?.cancel();
    _run?.cancel();
    super.dispose();
  }
}

/// The session as the compact plan the server takes (`previousPlan`): exercise
/// names with their sets, no notes. An exercise with no set is left out.
List<Map<String, dynamic>> compactPlan(List<Exercise> list) {
  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  for (final Exercise e in list) {
    if (e.sets.isEmpty) {
      continue;
    }
    out.add(<String, dynamic>{
      'name': e.name,
      if (e.isTime) 'measure': measureTime,
      'sets': <Map<String, dynamic>>[
        for (final SetEntry s in e.sets)
          if (e.isTime)
            <String, dynamic>{'minutes': s.minutes ?? 0, if (s.distanceKm != null) 'distanceKm': s.distanceKm}
          else
            <String, dynamic>{'reps': s.reps, 'kg': s.kg, 'max': s.isMax},
      ],
    });
  }
  return out;
}
