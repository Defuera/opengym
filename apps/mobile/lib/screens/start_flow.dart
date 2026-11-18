import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import 'other_activity_screen.dart';
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

/// The Log form of a time/distance activity named [activity].
void openLogForm(NavigatorState nav, AppDeps d, String activity) {
  final String n = activity.trim();
  nav.push(_route(OtherActivityScreen(
    store: d.store,
    activity: n.length > 40 ? n.substring(0, 40).trim() : n,
  )));
}

/// The coach's answer to a typed request: a prepared session, or (kind
/// "activity") the log form filled in.
void openProposal(NavigatorState nav, AppDeps d, StartProposal p) {
  if (p.kind == 'activity') {
    nav.push(_route(OtherActivityScreen(
      store: d.store,
      activity: p.type,
      focus: p.focus,
      minutes: p.minutes,
    )));
    return;
  }
  final Plan? plan = p.plan;
  final String rationale = (plan?.rationale ?? '').isEmpty ? p.reason : plan!.rationale;
  d.store.begin(
    activity: p.type,
    focus: p.focus,
    prepared: plan == null ? <Exercise>[] : d.plans.exercisesFor(plan),
    rationale: rationale,
  );
  nav.push(_route(_session(d)));
}
