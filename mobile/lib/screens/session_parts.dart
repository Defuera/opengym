import 'package:flutter/material.dart';

import '../models.dart';
import '../planner.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/dashed_box.dart';
import '../widgets/og_button.dart';
import '../widgets/stepper_row.dart';

/// The big middle card. Scrolls internally so nothing overflows on small phones.
class ExerciseCard extends StatelessWidget {
  const ExerciseCard({super.key, required this.store, required this.onSwap});

  final AppStore store;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final Exercise? ex = store.currentExercise;
    if (ex == null) {
      return DashedBox(
        radius: 20,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text('No exercises yet.', style: OG.body(weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Add one from the row above.', style: OG.muted()),
              ],
            ),
          ),
        ),
      );
    }
    final SetEntry? s = store.currentSet;
    final int cur = store.curSet;
    final bool fin = allDone(ex);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: ogBox(radius: 20),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(ex.name, style: OG.display(28)),
                ),
                const SizedBox(width: 12),
                OgButton(
                  minHeight: 48,
                  onPressed: onSwap,
                  child: const Text('Swap'),
                ),
              ],
            ),
            if (ex.fresh) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'First time here. Set your numbers once; next time they are pre-filled.',
                style: OG.muted(size: 14),
              ),
            ],
            const SizedBox(height: 14),
            _SetGrid(store: store, exercise: ex, finished: fin),
            if (s != null) ...<Widget>[
              const SizedBox(height: 14),
              StepperRow(
                label: '${s.isMax ? 'Max attempt' : 'Set ${cur + 1}'} · Reps',
                value: '${s.reps}',
                onMinus: () => store.changeReps(-1),
                onPlus: () => store.changeReps(1),
              ),
              const SizedBox(height: 14),
              StepperRow(
                label: 'Weight (kg)',
                value: fmtKg(s.kg),
                onMinus: () => store.changeKg(-2.5),
                onPlus: () => store.changeKg(2.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetGrid extends StatelessWidget {
  const _SetGrid({
    required this.store,
    required this.exercise,
    required this.finished,
  });

  final AppStore store;
  final Exercise exercise;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double w = ((box.maxWidth - 24) / 4).floorToDouble();
        final List<Widget> tiles = <Widget>[];
        for (int i = 0; i < exercise.sets.length; i++) {
          final SetEntry x = exercise.sets[i];
          final bool cur = i == store.curSet && !finished;
          tiles.add(_SetTile(
            width: w,
            set: x,
            index: i,
            current: cur,
            onTap: () => store.pickSet(i),
          ));
        }
        tiles.add(_ToolTile(width: w, label: '+ Set', onTap: store.addSet));
        if (exercise.sets.length > 1) {
          tiles.add(_ToolTile(
            width: w,
            label: '− Set',
            onTap: store.removeSet,
          ));
        }
        return Wrap(spacing: 8, runSpacing: 8, children: tiles);
      },
    );
  }
}

class _SetTile extends StatelessWidget {
  const _SetTile({
    required this.width,
    required this.set,
    required this.index,
    required this.current,
    required this.onTap,
  });

  final double width;
  final SetEntry set;
  final int index;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = current ? OG.white : OG.ink;
    final Color bg = current ? OG.ink : (set.done ? OG.done : OG.card);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: width,
        height: 62,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OG.ink, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Flexible(
                  child: Text(
                    set.isMax ? 'Max' : 'Set ${index + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OG.body(size: 12, weight: FontWeight.w600, color: fg),
                  ),
                ),
                Text(
                  set.done ? '✓' : '',
                  style: OG.body(size: 12, weight: FontWeight.w600, color: fg),
                ),
              ],
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${set.reps}×${fmtKg(set.kg)}',
                style: OG.display(17, color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.width,
    required this.label,
    required this.onTap,
  });

  final double width;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: 62,
        child: DashedBox(
          radius: 12,
          child: Center(
            child: Text(label, style: OG.body(size: 14, weight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}
