import 'package:flutter/material.dart';

import '../models.dart';
import '../planner.dart';
import '../theme.dart';
import '../widgets/labeled_field.dart';
import '../widgets/og_button.dart';
import '../widgets/og_chip.dart';
import '../widgets/stepper_row.dart';

/// What the add-goal sheet returns.
class GoalDraft {
  const GoalDraft({
    required this.title,
    required this.kind,
    this.exercise,
    this.targetKg,
    this.sessionsPerWeek,
  });

  final String title;
  final String kind;
  final String? exercise;
  final double? targetKg;
  final int? sessionsPerWeek;
}

String goalKindLabel(String kind) {
  switch (kind) {
    case 'strength':
      return 'Strength';
    case 'consistency':
      return 'Consistency';
    case 'work_around':
      return 'Work around';
    default:
      return 'Custom';
  }
}

Future<GoalDraft?> showGoalForm(BuildContext context) {
  return showModalBottomSheet<GoalDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: OG.ground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: OG.ink, width: 2),
    ),
    builder: (BuildContext ctx) => const _GoalForm(),
  );
}

class _GoalForm extends StatefulWidget {
  const _GoalForm();

  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _exercise = TextEditingController();
  String _kind = 'strength';
  double _kg = 0;
  int _perWeek = 0;

  @override
  void dispose() {
    _title.dispose();
    _exercise.dispose();
    super.dispose();
  }

  void _save() {
    final String title = _title.text.trim();
    if (title.isEmpty) {
      return;
    }
    final String ex = _exercise.text.trim();
    Navigator.of(context).pop(GoalDraft(
      title: title.length > 80 ? title.substring(0, 80) : title,
      kind: _kind,
      exercise: ex.isEmpty ? null : ex,
      targetKg: _kg > 0 ? _kg : null,
      sessionsPerWeek: _perWeek > 0 ? _perWeek : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.of(context).viewInsets.bottom;
    final double maxH = MediaQuery.of(context).size.height * 0.9;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 12 + keyboard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('New goal', style: OG.display(24)),
              const SizedBox(height: 14),
              LabeledField(label: 'Title', controller: _title, hint: 'What do you want?'),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String k in goalKinds)
                    OgChip(
                      label: goalKindLabel(k),
                      selected: _kind == k,
                      onTap: () => setState(() => _kind = k),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              LabeledField(
                label: 'Exercise (optional)',
                controller: _exercise,
                hint: exerciseLibrary.first,
              ),
              const SizedBox(height: 14),
              StepperRow(
                label: 'Target weight, kg (optional)',
                value: _kg > 0 ? fmtKg(_kg) : '–',
                onMinus: () => setState(() => _kg = _kg - 2.5 < 0 ? 0 : _kg - 2.5),
                onPlus: () => setState(() => _kg = _kg + 2.5),
              ),
              const SizedBox(height: 14),
              StepperRow(
                label: 'Sessions per week (optional)',
                value: _perWeek > 0 ? '$_perWeek' : '–',
                onMinus: () => setState(() => _perWeek = _perWeek > 0 ? _perWeek - 1 : 0),
                onPlus: () => setState(() => _perWeek = _perWeek < 7 ? _perWeek + 1 : 7),
              ),
              const SizedBox(height: 18),
              OgButton(
                variant: OgVariant.accent,
                onPressed: _save,
                child: const Text('Add goal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
