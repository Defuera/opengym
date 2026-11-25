import 'package:flutter/material.dart';

import '../models.dart';
import '../planner.dart';
import '../theme.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/set_list.dart';
import '../widgets/time_format.dart';
import '../widgets/time_list.dart';

/// The sets of one exercise of a past session, edited in place. It reuses the
/// live-session set widgets, but starts no timer and no rest clock and keeps
/// no "active session". Every change goes to the exercise, then [onChanged].
class ExerciseEditor extends StatelessWidget {
  const ExerciseEditor({
    super.key,
    required this.exercise,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
    required this.onRemove,
  });

  final Exercise exercise;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  List<SetEntry> get _sets => exercise.sets;

  SetEntry? get _cur => selected >= 0 && selected < _sets.length ? _sets[selected] : null;

  void _add() {
    final SetEntry? last = _sets.isEmpty ? null : _sets.last;
    if (exercise.isTime) {
      _sets.add(SetEntry.time(last?.minutes ?? defaultMinutes, distanceKm: last?.distanceKm, done: true));
    } else {
      _sets.add(SetEntry(reps: last?.reps ?? 8, kg: last?.kg ?? 0, done: true));
    }
    onSelect(_sets.length - 1);
    onChanged();
  }

  void _removeAt(int i) {
    if (_sets.length <= 1 || i < 0 || i >= _sets.length) {
      return;
    }
    _sets.removeAt(i);
    onSelect(selected > i ? selected - 1 : (selected >= _sets.length ? _sets.length - 1 : selected));
    onChanged();
  }

  void _reps(int d) {
    final SetEntry? s = _cur;
    if (s != null) {
      s.reps = (s.reps + d).clamp(0, 999).toInt();
      onChanged();
    }
  }

  void _kg(double d) {
    final SetEntry? s = _cur;
    if (s != null) {
      final double n = ((s.kg + d) * 100).round() / 100;
      s.kg = n < 0 ? 0.0 : n;
      onChanged();
    }
  }

  void _repsSet(int v) {
    final SetEntry? s = _cur;
    if (s != null && v >= 0 && v <= 999) {
      s.reps = v;
      onChanged();
    }
  }

  void _kgSet(double v) {
    final SetEntry? s = _cur;
    if (s != null && v >= 0 && v <= 1000) {
      s.kg = (v * 100).round() / 100;
      onChanged();
    }
  }

  void _failed(bool _) {
    final SetEntry? s = _cur;
    if (s != null) {
      s.failed = !s.failed;
      onChanged();
    }
  }

  void _minutes(double d) {
    final SetEntry? s = _cur;
    if (s != null && s.isTime) {
      s.minutes = stepMinutes(s.minutes ?? 0, d);
      onChanged();
    }
  }

  void _distance(double? km) {
    final SetEntry? s = _cur;
    if (s != null && s.isTime) {
      s.distanceKm = (km == null || km <= 0) ? null : km;
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: ogBox(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(exercise.name, style: OG.display(24))),
              OgIconButton(
                key: ValueKey<String>('edit-remove-${exercise.id}'),
                icon: Icons.delete_outline,
                onPressed: () async {
                  final bool ok = await confirmDelete(
                    context,
                    title: 'Remove this exercise?',
                    label: 'Remove exercise',
                  );
                  if (ok && context.mounted) {
                    onRemove();
                  }
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: exercise.isTime
                ? TimeList(
                    entries: <TimeRowData>[
                      for (final SetEntry x in _sets)
                        TimeRowData(
                          id: x,
                          minutes: x.minutes ?? 0,
                          distanceKm: x.distanceKm == null ? null : fmtKg(x.distanceKm!),
                        ),
                    ],
                    selected: selected,
                    onSelect: onSelect,
                    onAdd: _add,
                    onRemove: _removeAt,
                    onMinutesChanged: _minutes,
                    onDistanceChanged: _distance,
                  )
                : SetList(
                    sets: <SetRowData>[
                      for (final SetEntry x in _sets)
                        SetRowData(id: x, reps: x.reps, kg: fmtKg(x.kg), failed: x.failed, isMax: x.isMax),
                    ],
                    selected: selected,
                    onSelect: onSelect,
                    onAdd: _add,
                    onRemove: _removeAt,
                    onRepsChanged: _reps,
                    onKgChanged: _kg,
                    onRepsSet: _repsSet,
                    onKgSet: _kgSet,
                    onFailedChanged: _failed,
                  ),
          ),
        ],
      ),
    );
  }
}
