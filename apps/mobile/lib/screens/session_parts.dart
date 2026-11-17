import 'package:flutter/material.dart';

import '../models.dart';
import '../planner.dart';
import '../store.dart';
import '../widgets/exercise_card.dart';
import '../widgets/exercise_carousel.dart';
import '../widgets/exercise_panel.dart';
import '../widgets/item_state.dart';
import '../widgets/note_box.dart';
import '../widgets/set_list.dart';

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
        onDiscard: () => store.discardExercise(i),
      ));
    }
    return ExerciseCarousel(
      selectedIndex: store.curEx,
      onReorder: store.moveExercise,
      footer: AddCard(onTap: onAdd),
      children: cards,
    );
  }
}

/// Maps the current exercise onto the big card (title plus list of sets).
class SessionPanel extends StatelessWidget {
  const SessionPanel({super.key, required this.store});

  final AppStore store;

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
    return ExercisePanel(
      name: ex.name,
      hint: _hint(ex),
      children: <Widget>[
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
        ),
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
