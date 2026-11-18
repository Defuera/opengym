import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/deps.dart';
import '../models.dart';
import '../planner.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/cta_button.dart';
import '../widgets/exercise_picker.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/og_sheet.dart';
import '../widgets/preparing_card.dart';
import '../widgets/proposal_feedback.dart';
import '../widgets/session_meta_row.dart';
import '../stores/proposal_rebuild.dart';
import 'place_mark_view.dart';
import 'session_parts.dart';
import 'session_recap_screen.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.store,
    this.deps,
    this.rebuild,
  });

  final AppStore store;

  /// With [deps], finishing a session ends on its recap. Without, on Home.
  final AppDeps? deps;

  /// Set on a coach proposal: "Change plan" shows until a set is done.
  final ProposalRebuild? rebuild;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final TextEditingController _feedback = TextEditingController();
  bool _wasBusy = false;

  AppStore get store => widget.store;
  AppDeps? get deps => widget.deps;
  ProposalRebuild? get rebuild => widget.rebuild;

  @override
  void initState() {
    super.initState();
    rebuild?.addListener(_onRebuild);
  }

  @override
  void dispose() {
    rebuild?.removeListener(_onRebuild);
    _feedback.dispose();
    super.dispose();
  }

  /// The typed text is cleared after a rebuild went through, kept after a failure.
  void _onRebuild() {
    final ProposalRebuild r = rebuild!;
    if (_wasBusy && !r.busy && !r.failed) {
      _feedback.clear();
    }
    _wasBusy = r.busy;
  }

  void _minimise(BuildContext context) {
    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
  }

  Future<void> _showWhy(BuildContext context, Session a) {
    return showOgSheet<void>(
      context,
      (BuildContext c) => WhySessionBody(focus: a.focus, rationale: a.planNote),
      title: 'Why this session',
    );
  }

  Future<void> _showChangePlan(BuildContext context) {
    final ProposalRebuild r = rebuild!;
    return showOgSheet<void>(
      context,
      (BuildContext c) => ListenableBuilder(
        listenable: Listenable.merge(<Listenable?>[r, deps?.connection].whereType<Listenable>().toList()),
        builder: (BuildContext c, Widget? w) => ProposalFeedback(
          controller: _feedback,
          failed: r.failed,
          online: deps?.connection.connected ?? true,
          onRebuild: (String t) {
            Navigator.of(c).pop();
            r.rebuild(t);
          },
        ),
      ),
      title: 'Change plan',
    );
  }

  void _leave(BuildContext context, {String? recapId}) {
    final NavigatorState nav = Navigator.of(context);
    nav.popUntil((Route<dynamic> r) => r.isFirst);
    final AppDeps? d = deps;
    if (recapId != null && d != null) {
      nav.push(MaterialPageRoute<void>(
        builder: (BuildContext c) => SessionRecapScreen(deps: d, sessionId: recapId),
      ));
    }
  }

  Future<void> _close(BuildContext context) async {
    final String? choice = await showChoiceSheet(
      context,
      title: 'End this session?',
      choices: const <SheetChoice>[
        SheetChoice(
          value: 'finish',
          label: 'Finish and save',
          variant: OgVariant.accent,
        ),
        SheetChoice(value: 'discard', label: 'Discard without saving'),
        SheetChoice(
          value: 'keep',
          label: 'Keep going',
          variant: OgVariant.dashed,
        ),
      ],
    );
    String? saved;
    if (choice == 'finish') {
      saved = store.finish();
    } else if (choice == 'discard') {
      store.discard();
    } else {
      return;
    }
    if (context.mounted) {
      _leave(context, recapId: saved);
    }
  }

  Future<void> _addExercise(BuildContext context) async {
    final Session? a = store.active;
    if (a == null) {
      return;
    }
    final ExerciseChoice? pick = await showExercisePicker(
      context,
      title: 'Add exercise',
      options: <ExerciseOption>[
        for (final LoggedExercise x in loggedExercises(store.sessions))
          ExerciseOption(x.name, timed: x.measure == measureTime),
      ],
    );
    if (pick == null || pick.name.isEmpty) {
      return;
    }
    store.addExercise(pick.name, measure: pick.timed ? measureTime : measureSets);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable?>[store, rebuild, deps?.connection].whereType<Listenable>().toList()),
      builder: (BuildContext context, Widget? child) {
        final Session? a = store.active;
        if (a == null) {
          return const Scaffold(body: SizedBox.shrink());
        }
        final bool canChange = rebuild != null && !store.hasDoneSet;
        final bool busy = canChange && rebuild!.busy;
        final bool why = a.focus != null || a.planNote != null;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            a.type,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: OG.display(a.type.length > 24 ? 26 : 30),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OgIconButton(
                        icon: Icons.keyboard_arrow_down,
                        onPressed: () => _minimise(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 20, 0),
                  child: SessionMetaRow(
                    note: (rebuild?.failed ?? false) && !busy ? 'Could not rebuild. Try again.' : null,
                    items: <Widget>[
                      if (deps != null)
                        PlaceMarkView(deps: deps!, placeId: a.placeId, onPick: store.setActivePlace),
                      if (why) MetaItem(label: 'Why this?', onTap: () => _showWhy(context, a)),
                      if (canChange) MetaItem(label: 'Change plan', onTap: () => _showChangePlan(context)),
                      MetaItem(label: 'End session', onTap: () => _close(context)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (busy)
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: PreparingCard(
                        title: 'Rebuilding…',
                        message: 'The coach changes the session with your feedback.',
                        actionLabel: 'Keep this session',
                        onAction: rebuild!.cancel,
                      ),
                    ),
                  )
                else ...<Widget>[
                  ExerciseStrip(
                    store: store,
                    onAdd: () => _addExercise(context),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                      child: SessionPanel(store: store),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  child: _cta(context, a),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cta(BuildContext context, Session a) {
    final Exercise? ex = store.currentExercise;
    final bool last = store.curEx >= a.exercises.length - 1;
    if (ex != null && !allDone(ex)) {
      return CtaButton(
        label: ex.isTime ? 'Complete' : 'Complete set',
        icon: Icons.check,
        variant: OgVariant.accent,
        onPressed: () {
          HapticFeedback.mediumImpact();
          store.completeSet();
        },
      );
    }
    if (ex != null && !last) {
      return CtaButton(
        label: 'Next exercise',
        icon: Icons.arrow_forward,
        iconAfter: true,
        onPressed: store.nextExercise,
      );
    }
    return CtaButton(
      label: 'Finish session',
      icon: Icons.check,
      onPressed: () {
        _leave(context, recapId: store.finish());
      },
    );
  }
}
