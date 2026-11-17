import 'package:flutter/material.dart';

import '../models.dart';
import '../planner.dart';
import '../store.dart';
import '../widgets/exercise_card.dart';
import '../widgets/exercise_carousel.dart';
import '../widgets/exercise_panel.dart';
import '../widgets/flag_toggle.dart';
import '../widgets/item_state.dart';
import '../widgets/note_box.dart';
import '../widgets/set_tile.dart';
import '../widgets/stepper_row.dart';

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
        name: e.name,
        progressLabel: fin ? 'Done' : '$done / ${e.sets.length} sets',
        state: i == store.curEx ? ItemState.current : (fin ? ItemState.finished : ItemState.idle),
        canMoveEarlier: i > 0,
        onTap: () => store.pickExercise(i),
        onMoveEarlier: () => store.moveExerciseEarlier(i),
        onDiscard: () => store.discardExercise(i),
      ));
    }
    cards.add(AddCard(onTap: onAdd));
    return ExerciseCarousel(selectedIndex: store.curEx, children: cards);
  }
}

/// Maps the current exercise onto the big card (sets grid plus steppers).
class SessionPanel extends StatelessWidget {
  const SessionPanel({super.key, required this.store, required this.onSwap});

  final AppStore store;
  final VoidCallback onSwap;

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
    final SetEntry? s = store.currentSet;
    final bool fin = allDone(ex);
    final List<Widget> tiles = <Widget>[];
    for (int i = 0; i < ex.sets.length; i++) {
      final SetEntry x = ex.sets[i];
      tiles.add(SetTile(
        label: x.isMax ? 'Max' : 'Set ${i + 1}',
        value: '${x.reps}${x.failed ? '½' : ''}×${fmtKg(x.kg)}',
        state: (i == store.curSet && !fin)
            ? ItemState.current
            : (x.done ? ItemState.finished : ItemState.idle),
        checked: x.done,
        onTap: () => store.pickSet(i),
      ));
    }
    tiles.add(ToolTile(label: '+ Set', onTap: store.addSet));
    if (ex.sets.length > 1) {
      tiles.add(ToolTile(label: '− Set', onTap: store.removeSet));
    }
    final List<Widget> body = <Widget>[];
    if (s != null) {
      body.add(StepperRow(
        label: '${s.isMax ? 'Max attempt' : 'Set ${store.curSet + 1}'} · Reps',
        value: '${s.reps}',
        onMinus: () => store.changeReps(-1),
        onPlus: () => store.changeReps(1),
      ));
      body.add(StepperRow(
        label: 'Weight (kg)',
        value: fmtKg(s.kg),
        onMinus: () => store.changeKg(-2.5),
        onPlus: () => store.changeKg(2.5),
      ));
      // "6½" on the tile: one more rep was tried and not completed.
      body.add(FlagToggle(
        label: 'Last rep failed',
        value: s.failed,
        onChanged: (bool _) => store.toggleFailed(),
      ));
    }
    return ExercisePanel(
      name: ex.name,
      hint: _hint(ex),
      onSwap: onSwap,
      pinned: <Widget>[SetGrid(children: tiles)],
      children: body,
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
