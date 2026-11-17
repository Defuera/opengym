import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../planner.dart';
import '../store.dart';
import '../stores/plan_store.dart';
import '../theme.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/cta_button.dart';
import '../widgets/exercise_picker.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import 'session_focus_bar.dart';
import 'session_parts.dart';

class SessionScreen extends StatelessWidget {
  const SessionScreen({
    super.key,
    required this.store,
    this.plans,
    this.online = false,
    this.advisedFocus,
  });

  final AppStore store;

  /// When set, the focus chips show before the first set is done.
  final PlanStore? plans;
  final bool online;
  final String? advisedFocus;

  void _leave(BuildContext context) {
    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
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
    if (choice == 'finish') {
      store.finish();
    } else if (choice == 'discard') {
      store.discard();
    } else {
      return;
    }
    if (context.mounted) {
      _leave(context);
    }
  }

  Future<void> _addExercise(BuildContext context) async {
    final Session? a = store.active;
    if (a == null) {
      return;
    }
    final List<String> used = a.exercises.map((Exercise e) => e.name).toList();
    final String? name = await showExercisePicker(
      context,
      title: 'Add exercise',
      options: exerciseLibrary.where((String n) => !used.contains(n)).toList(),
    );
    if (name == null || name.isEmpty) {
      return;
    }
    store.addExercise(name);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
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
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: OG.muted(size: 14, weight: FontWeight.w600),
                            ),
                            Text(
                              a.type,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OG.display(32),
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
                if (plans != null)
                  SessionFocusBar(
                    store: store,
                    plans: plans!,
                    online: online,
                    advised: advisedFocus,
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
        label: 'Complete set',
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
        store.finish();
        _leave(context);
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
