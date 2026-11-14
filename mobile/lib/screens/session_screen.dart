import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../planner.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/exercise_picker.dart';
import '../widgets/og_button.dart';
import 'session_carousel.dart';
import 'session_parts.dart';

class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key, required this.store});

  final AppStore store;

  void _leave(BuildContext context) {
    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
  }

  Future<void> _close(BuildContext context) async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: OG.ground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: OG.ink, width: 2),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('End this session?', style: OG.display(24)),
                const SizedBox(height: 14),
                OgButton(
                  variant: OgVariant.accent,
                  onPressed: () => Navigator.of(ctx).pop('finish'),
                  child: const Text('Finish and save'),
                ),
                const SizedBox(height: 8),
                OgButton(
                  onPressed: () => Navigator.of(ctx).pop('discard'),
                  child: const Text('Discard without saving'),
                ),
                const SizedBox(height: 8),
                OgButton(
                  variant: OgVariant.dashed,
                  onPressed: () => Navigator.of(ctx).pop('keep'),
                  child: const Text('Keep going'),
                ),
              ],
            ),
          ),
        );
      },
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

  Future<void> _pick(BuildContext context, {required bool swap}) async {
    final Session? a = store.active;
    if (a == null) {
      return;
    }
    final String title =
        swap ? 'Swap ${store.currentExercise?.name ?? ''}' : 'Add exercise';
    final List<String> used = a.exercises.map((Exercise e) => e.name).toList();
    final String? name = await showExercisePicker(
      context,
      title: title,
      used: used,
    );
    if (name == null || name.isEmpty) {
      return;
    }
    if (swap) {
      store.swapExercise(name);
    } else {
      store.addExercise(name);
    }
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
                              'Prepared from your log',
                              style: OG.muted(size: 14, weight: FontWeight.w600),
                            ),
                            Text(
                              'Gym · ${a.type}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OG.display(32),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 52,
                        child: OgButton(
                          minHeight: 52,
                          padding: EdgeInsets.zero,
                          onPressed: () => _close(context),
                          child: const Icon(Icons.close, size: 24),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ExerciseCarousel(
                  store: store,
                  onAdd: () => _pick(context, swap: false),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ExerciseCard(
                      store: store,
                      onSwap: () => _pick(context, swap: true),
                    ),
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
      return SizedBox(
        width: double.infinity,
        child: OgButton(
          variant: OgVariant.accent,
          minHeight: 76,
          radius: 20,
          onPressed: () {
            HapticFeedback.mediumImpact();
            store.completeSet();
          },
          child: _ctaLabel('Complete set', Icons.check),
        ),
      );
    }
    if (ex != null && !last) {
      return SizedBox(
        width: double.infinity,
        child: OgButton(
          variant: OgVariant.ink,
          minHeight: 76,
          radius: 20,
          onPressed: store.nextExercise,
          child: _ctaLabel('Next exercise', Icons.arrow_forward, trailing: true),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OgButton(
        variant: OgVariant.ink,
        minHeight: 76,
        radius: 20,
        onPressed: () {
          store.finish();
          _leave(context);
        },
        child: _ctaLabel('Finish session', Icons.check),
      ),
    );
  }

  Widget _ctaLabel(String text, IconData icon, {bool trailing = false}) {
    final Widget label = Text(text, style: OG.display(24, color: OG.white));
    final Widget ic = Icon(icon, size: 30);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: trailing
          ? <Widget>[label, const SizedBox(width: 8), ic]
          : <Widget>[ic, const SizedBox(width: 8), label],
    );
  }
}
