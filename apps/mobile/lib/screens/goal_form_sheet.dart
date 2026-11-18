import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/labeled_field.dart';
import '../widgets/og_button.dart';
import '../widgets/og_sheet.dart';

String goalKindLabel(String kind) {
  switch (kind) {
    case 'strength':
      return 'Strength';
    case 'consistency':
      return 'Consistency';
    default:
      return 'Custom';
  }
}

/// The goal sheet: one text field. Returns the trimmed text, or null when closed.
/// With [initialText] it edits a goal. The structure (kind, exercise, target)
/// is read from the text by the backend a moment after the goal is saved.
Future<String?> showGoalForm(BuildContext context, {String? initialText}) {
  final bool editing = initialText != null;
  return showOgSheet<String>(
    context,
    (BuildContext ctx) => _GoalForm(initialText: initialText, editing: editing),
    title: editing ? 'Edit goal' : 'New goal',
  );
}

class _GoalForm extends StatefulWidget {
  const _GoalForm({required this.initialText, required this.editing});

  final String? initialText;
  final bool editing;

  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  late final TextEditingController _text = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final String text = _text.text.trim();
    if (text.isEmpty) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus(); // the keyboard closes with the sheet
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LabeledField(
          label: 'What do you want?',
          controller: _text,
          hint: 'Bench press 70 kg by spring',
          minLines: 2,
          maxLines: 5,
          maxLength: goalTitleMax,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
        ),
        const SizedBox(height: 18),
        OgButton(
          variant: OgVariant.accent,
          onPressed: _save,
          child: Text(widget.editing ? 'Save goal' : 'Add goal'),
        ),
      ],
    );
  }
}
