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
import '../widgets/proposal_feedback.dart';
import '../stores/proposal_rebuild.dart';
import 'place_mark_view.dart';
import 'session_parts.dart';
import 'session_recap_screen.dart';

class SessionScreen extends StatelessWidget {
  const SessionScreen({
    super.key,
    required this.store,
    this.deps,
    this.rebuild,
  });

  final AppStore store;

  /// With [deps], finishing a session ends on its recap. Without, on Home.
  final AppDeps? deps;

  /// Set on a coach proposal: a feedback field and "Rebuild" show until a set is done.
  final ProposalRebuild? rebuild;

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
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              sessionSubtitle(a),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: OG.muted(size: 14, weight: FontWeight.w600),
                            ),
                            Text(
                              a.type,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OG.display(32),
                            ),
                            if (deps != null)
                              PlaceMarkView(
                                deps: deps!,
                                placeId: a.placeId,
                                onPick: store.setActivePlace,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      OgIconButton(
                        icon: Icons.close,
                        onPressed: () => _close(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ExerciseStrip(
                  store: store,
                  onAdd: () => _addExercise(context),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SessionPanel(store: store),
                  ),
                ),
                if (rebuild != null && !store.hasDoneSet)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: ProposalFeedback(
                      busy: rebuild!.busy,
                      failed: rebuild!.failed,
                      online: deps?.connection.connected ?? true,
                      onRebuild: rebuild!.rebuild,
                      onKeep: rebuild!.cancel,
                    ),
                  ),
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

/// The small line under the activity name: the focus, then where the session
/// came from, e.g. "Upper · prepared from your log".
String sessionSubtitle(Session a) {
  final String note = a.planNote ?? 'prepared from your log';
  final String? f = a.focus;
  return f == null ? note : '$f · $note';
}
