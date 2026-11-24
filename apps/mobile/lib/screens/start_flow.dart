import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../stores/proposal_rebuild.dart';
import '../stores/start_run.dart';
import 'activity_log_form.dart';
import 'prepare_session_screen.dart';
import 'program_screen.dart';
import 'session_screen.dart';

/// How a start choice opens a session. [nav] is the navigator under the sheet.

Route<void> _route(Widget screen) => MaterialPageRoute<void>(builder: (BuildContext c) => screen);

SessionScreen _session(AppDeps d, {StartFallback? fallback}) =>
    SessionScreen(store: d.store, deps: d, rebuild: rebuildFor(d, fallback: fallback));

/// Why a session opened from the app's own plan after a start request: the
/// [notice] the person reads, the [note] for today they gave, and the run that
/// still waits for a [late] answer of the coach (null when the request failed).
class StartFallback {
  const StartFallback({required this.notice, this.note, this.late});

  final String notice;
  final String? note;
  final StartRun? late;
}

/// A stored proposal: the prepared session of [activity] + [focus]. An open
/// session is resumed; offline (or with no focus) it starts from the local
/// fallback plan at once; online the stored plan is read (a few seconds at
/// most) by the prepare screen. With [local] the stored plan is not read: the
/// session starts from the local fallback plan at once. [fallback] says that
/// the coach was asked first and did not answer.
void openPrepared(NavigatorState nav, AppDeps d,
    {required String activity, String? focus, bool local = false, StartFallback? fallback}) {
  if (local || d.store.hasDoneSet || !d.connection.connected || focus == null) {
    d.store.begin(activity: activity, focus: focus);
    nav.push(_route(_session(d, fallback: fallback)));
    return;
  }
  nav.push(_route(PrepareSessionScreen(deps: d, activity: activity, focus: focus)));
}

/// An empty session (no plan) named [activity].
void openEmpty(NavigatorState nav, AppDeps d, {String activity = gymType, StartFallback? fallback}) {
  d.store.begin(activity: activity, prepared: <Exercise>[]);
  nav.push(_route(_session(d, fallback: fallback)));
}

/// The form (one text) of a time/distance activity named [activity].
void openLogForm(NavigatorState nav, AppDeps d, String activity) {
  final String n = activity.trim();
  nav.push(_route(ActivityLogForm(
    deps: d,
    activity: n.length > 40 ? n.substring(0, 40).trim() : n,
  )));
}

/// The coach's answer to a typed request: a prepared session, or (kind
/// "activity") the log form of that activity.
///
/// [requestId] is the request that made [p]. With it the session screen offers
/// the coach's late plan, when there is one.
void openProposal(NavigatorState nav, AppDeps d, StartProposal p, {String? requestId}) {
  if (p.kind == 'activity') {
    openLogForm(nav, d, p.type);
    return;
  }
  _beginProposal(d, p);
  nav.push(_route(SessionScreen(store: d.store, deps: d, rebuild: rebuildFor(d, requestId: requestId))));
}

/// What the session screen shows of the coach's plan: the notice and the late
/// offer of [fallback]. [requestId] is kept for the callers; it is not used.
ProposalRebuild rebuildFor(AppDeps d, {String? requestId, StartFallback? fallback}) => ProposalRebuild(
      notice: fallback?.notice,
      late: fallback?.late,
      onProposal: (StartProposal n) => _replaceProposal(d, n),
    );

/// The Program screen of the program [programId].
void openProgram(NavigatorState nav, AppDeps d, String programId) {
  nav.push(_route(ProgramScreen(deps: d, programId: programId)));
}

/// Starts the session of [p]. A proposal that the coach built from a program
/// carries the program link; [program] is the link to keep when it has none.
void _beginProposal(AppDeps d, StartProposal p, {ProgramLink? program}) {
  final Plan? plan = p.plan;
  final String rationale = (plan?.rationale ?? '').isEmpty ? p.reason : plan!.rationale;
  d.store.begin(
    activity: p.type,
    focus: p.focus,
    prepared: plan == null ? <Exercise>[] : d.plans.exercisesFor(plan),
    rationale: rationale,
    placeId: p.place?.id,
    program: p.program ?? program,
  );
  final PlaceRef? place = p.place;
  if (place != null) {
    d.places.learn(place);
  }
}

/// Swaps the shown proposal for a rebuilt one. Only a session with no done set
/// is replaced, so logged work is never lost. False when nothing was replaced.
bool _replaceProposal(AppDeps d, StartProposal p) {
  if (d.store.active == null || d.store.hasDoneSet) {
    return false;
  }
  // A rebuilt proposal with no place keeps the place the person has now.
  final String? keep = d.store.active?.placeId;
  // The program link of a program session survives the replace.
  _beginProposal(d, p, program: d.store.active?.program);
  if (p.place == null) {
    d.store.setActivePlace(keep);
  }
  return true;
}
