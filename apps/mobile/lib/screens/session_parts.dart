import 'package:flutter/material.dart';

import '../models.dart';
import '../planner.dart';
import '../store.dart';
import '../stores/countdown_store.dart';
import '../stores/exercise_art_store.dart';
import '../theme.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/ask_coach_line.dart';
import '../widgets/comment_line.dart';
import '../widgets/exercise_anim.dart';
import '../widgets/exercise_card.dart';
import '../widgets/exercise_carousel.dart';
import '../widgets/exercise_panel.dart';
import '../widgets/item_state.dart';
import '../widgets/note_box.dart';
import '../widgets/og_sheet.dart';
import '../widgets/set_list.dart';
import '../widgets/time_list.dart';

/// Maps the active session's exercises onto the carousel.
class ExerciseStrip extends StatelessWidget {
  const ExerciseStrip({super.key, required this.store, required this.onAdd});

  final AppStore store;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final List<Exercise> list = store.active?.exercises ?? <Exercise>[];
    final List<Widget> cards = <Widget>[];
    for (int i = 0; i < list.length; i++) {
      final Exercise e = list[i];
      final bool fin = allDone(e);
      final int done = e.sets.where((SetEntry s) => s.done).length;
      cards.add(ExerciseCard(
        key: ValueKey<String>(e.id),
        name: e.name,
        progressLabel: '$done / ${e.sets.length}',
        state: i == store.curEx ? ItemState.current : (fin ? ItemState.finished : ItemState.idle),
        onTap: () => store.pickExercise(i),
        onDiscard: () async {
          final bool ok = await confirmDelete(context, title: 'Remove this exercise?', label: 'Remove exercise');
          if (ok && context.mounted) {
            store.discardExercise(i);
          }
        },
      ));
    }
    // The add button stays at the right of the strip: it does not scroll away.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Stack(
            children: <Widget>[
              ExerciseCarousel(
                selectedIndex: store.curEx,
                onReorder: store.moveExercise,
                endPad: 24,
                children: cards,
              ),
              // The cards fade out before the add button, so the button never looks as if it covers one.
              const Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 24,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: <Color>[Color(0x00F2F1EC), OG.ground]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 20, 0),
          child: AddCard(key: const ValueKey<String>('add-exercise'), onTap: onAdd, label: 'Add exercise', compact: true),
        ),
      ],
    );
  }
}

/// Maps the current exercise onto the big card (title plus list of sets).
class SessionPanel extends StatelessWidget {
  const SessionPanel({super.key, required this.store, this.art, this.onAskCoach});

  /// Opens the chat about this exercise. Null: no "Change this exercise" line.
  final VoidCallback? onAskCoach;

  final AppStore store;

  /// The exercise pictures. Null: no picture shows.
  final ExerciseArtStore? art;

  @override
  Widget build(BuildContext context) {
    final Exercise? ex = store.currentExercise;
    if (ex == null) {
      return const NoteBox(
        title: 'No exercises yet.',
        message: 'Add one from the row above.',
        centered: true,
      );
    }
    final ImageProvider? image = art?.imageFor(ex.name);
    return ListenableBuilder(
      listenable: store.countdown,
      builder: (BuildContext c, Widget? w) => _panel(ex, image),
    );
  }

  Widget _panel(Exercise ex, ImageProvider? image) {
    final CountdownStore cd = store.countdown;
    int? cdIndex;
    for (int i = 0; i < ex.sets.length; i++) {
      if (cd.isFor(ex.sets[i])) {
        cdIndex = i;
      }
    }
    return ExercisePanel(
      name: ex.name,
      hint: _hint(ex),
      trailing: image == null ? null : _ArtThumb(name: ex.name, image: image),
      children: <Widget>[
        if (ex.isTime)
          TimeList(
            entries: <TimeRowData>[
              for (final SetEntry x in ex.sets)
                TimeRowData(
                  id: x,
                  minutes: x.minutes ?? 0,
                  distanceKm: x.distanceKm == null ? null : fmtKg(x.distanceKm!),
                  done: x.done,
                ),
            ],
            selected: store.curSet,
            onSelect: store.pickSet,
            onAdd: store.addSet,
            onRemove: store.removeSetAt,
            onMinutesChanged: store.changeMinutes,
            onMinutesSet: store.setMinutes,
            onDistanceChanged: store.setDistance,
            onToggle: store.toggleSet,
            checkPrefix: 'set-check-${store.curEx}',
            countdownIndex: cdIndex,
            remaining: cd.remaining,
            paused: cd.paused,
            onStart: () => store.startCountdown(store.curSet),
            onPauseResume: () => cd.paused ? cd.resume() : cd.pause(),
            onReset: cd.cancel,
          )
        else
          SetList(
          sets: <SetRowData>[
            for (final SetEntry x in ex.sets)
              SetRowData(
                id: x,
                reps: x.reps,
                kg: fmtKg(x.kg),
                done: x.done,
                failed: x.failed,
                isMax: x.isMax,
              ),
          ],
          selected: store.curSet,
          onSelect: store.pickSet,
          onAdd: store.addSet,
          onRemove: store.removeSetAt,
          onRepsChanged: store.changeReps,
          onKgChanged: store.changeKg,
          onFailedChanged: (bool _) => store.toggleFailed(),
          onToggle: store.toggleSet,
          checkPrefix: 'set-check-${store.curEx}',
        ),
        CommentLine(comment: ex.comment, onChanged: store.setComment),
        if (onAskCoach != null) AskCoachLine(onTap: onAskCoach!),
      ],
    );
  }
}

String? _hint(Exercise ex) {
  final String? note = ex.note;
  final String? fresh =
      ex.fresh ? 'First time here. Set your numbers once; next time they are pre-filled.' : null;
  if (note != null && note.isNotEmpty) {
    return fresh == null ? note : '$note\n$fresh';
  }
  return fresh;
}

/// The small picture at the right of the exercise title. A tap opens it large.
class _ArtThumb extends StatelessWidget {
  const _ArtThumb({required this.name, required this.image});

  final String name;
  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey<String>('exercise-anim'),
      behavior: HitTestBehavior.opaque,
      onTap: () => showOgSheet<void>(
        context,
        (BuildContext c) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: ExerciseAnim(key: const ValueKey<String>('exercise-anim-large'), image: image),
            ),
          ),
        ),
        title: name,
      ),
      child: ExerciseAnim(image: image, size: 72, square: true),
    );
  }
}
