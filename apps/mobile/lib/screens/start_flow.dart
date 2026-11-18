import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../stores/proposal_rebuild.dart';
import 'log_text_screen.dart';
import 'prepare_session_screen.dart';
import 'session_screen.dart';

/// How a start choice opens a session. [nav] is the navigator under the sheet.

Route<void> _route(Widget screen) => MaterialPageRoute<void>(builder: (BuildContext c) => screen);

SessionScreen _session(AppDeps d) => SessionScreen(store: d.store, deps: d);

/// A stored proposal: the prepared session of [activity] + [focus]. An open
/// session is resumed; offline (or with no focus) it starts from the local
/// fallback plan at once; online the stored plan is read (a few seconds at
/// most) by the prepare screen. With [local] the stored plan is not read: the
/// session starts from the local fallback plan at once.
void openPrepared(NavigatorState nav, AppDeps d, {required String activity, String? focus, bool local = false}) {
  if (local || d.store.hasDoneSet || !d.connection.connected || focus == null) {
    d.store.begin(activity: activity, focus: focus);
    nav.push(_route(_session(d)));
    return;
  }
  nav.push(_route(PrepareSessionScreen(deps: d, activity: activity, focus: focus)));
}

/// An empty session (no plan) named [activity].
void openEmpty(NavigatorState nav, AppDeps d, {String activity = gymType}) {
  d.store.begin(activity: activity, prepared: <Exercise>[]);
  nav.push(_route(_session(d)));
}

/// The Log form (one text) of a time/distance activity named [activity].
void openLogForm(NavigatorState nav, AppDeps d, String activity) {
  final String n = activity.trim();
  nav.push(_route(LogTextScreen(
    deps: d,
    activity: n.length > 40 ? n.substring(0, 40).trim() : n,
  )));
}

/// The coach's answer to a typed request: a prepared session, or (kind
/// "activity") the log form of that activity.
///
/// [requestId] is the request that made [p]. With it the session screen offers
/// feedback and a rebuild, until the first set is done.
void openProposal(NavigatorState nav, AppDeps d, StartProposal p, {String? requestId}) {
  if (p.kind == 'activity') {
    openLogForm(nav, d, p.type);
    return;
  }
  _beginProposal(d, p);
  final ProposalRebuild? rebuild = requestId == null
      ? null
      : ProposalRebuild(plans: d.plans, requestId: requestId, onProposal: (StartProposal n) => _replaceProposal(d, n));
  nav.push(_route(SessionScreen(store: d.store, deps: d, rebuild: rebuild)));
}

void _beginProposal(AppDeps d, StartProposal p) {
  final Plan? plan = p.plan;
  final String rationale = (plan?.rationale ?? '').isEmpty ? p.reason : plan!.rationale;
  d.store.begin(
    activity: p.type,
    focus: p.focus,
    prepared: plan == null ? <Exercise>[] : d.plans.exercisesFor(plan),
    rationale: rationale,
    placeId: p.place?.id,
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
  _beginProposal(d, p);
  if (p.place == null) {
    d.store.setActivePlace(keep);
  }
  return true;
}
