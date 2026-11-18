import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'og_button.dart';
import 'og_sheet.dart';

/// An exercise of the user's log: its spelling and whether it is measured in time.
class ExerciseOption {
  const ExerciseOption(this.name, {this.timed = false});

  final String name;
  final bool timed;
}

/// What the sheet returns: the name to add and how it is measured.
class ExerciseChoice {
  const ExerciseChoice(this.name, {this.timed = false});

  final String name;
  final bool timed;
}

/// Bottom sheet to add an exercise. [options] are the exercises of the user's
/// log, most recently used first (nothing is built in). Typing filters them:
/// every typed word must be part of the name. A name that is not in the log
/// can be added; then the sheet asks how it is measured. Returns null when
/// dismissed.
Future<ExerciseChoice?> showExercisePicker(
  BuildContext context, {
  required String title,
  required List<ExerciseOption> options,
}) {
  return showOgSheet<ExerciseChoice>(
    context,
    (BuildContext ctx) => _PickerSheet(options: options),
    title: title,
    scroll: false,
  );
}

String _key(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// First letter upper case, the rest as typed, spaces collapsed.
String _newName(String typed) {
  final String t = typed.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.options});

  final List<ExerciseOption> options;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final TextEditingController _controller = TextEditingController();

  /// Set when a new name waits for its measure.
  String? _asking;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<ExerciseOption> get _matches {
    final List<String> words = _key(_controller.text).split(' ').where((String w) => w.isNotEmpty).toList();
    if (words.isEmpty) {
      return widget.options;
    }
    return widget.options.where((ExerciseOption o) {
      final String k = _key(o.name);
      return words.every(k.contains);
    }).toList();
  }

  ExerciseOption? get _exact {
    final String k = _key(_controller.text);
    for (final ExerciseOption o in widget.options) {
      if (_key(o.name) == k) {
        return o;
      }
    }
    return null;
  }

  void _pick(ExerciseOption o) => Navigator.of(context).pop(ExerciseChoice(o.name, timed: o.timed));

  /// The Add button and the keyboard's Done: reuse the log's spelling for an
  /// exact match, else ask how the new name is measured.
  void _submit() {
    if (_controller.text.trim().isEmpty) {
      return;
    }
    final ExerciseOption? same = _exact;
    if (same != null) {
      _pick(same);
      return;
    }
    setState(() => _asking = _newName(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final String? asking = _asking;
    if (asking != null) {
      return _MeasureQuestion(
        name: asking,
        onChoose: (bool timed) => Navigator.of(context).pop(ExerciseChoice(asking, timed: timed)),
      );
    }
    final OutlineInputBorder idle = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: OG.ink, width: 2),
    );
    final OutlineInputBorder focused = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: OG.accent, width: 3),
    );
    final String typed = _controller.text.trim();
    final List<ExerciseOption> matches = _matches;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(60),
          ],
          onChanged: (String _) => setState(() {}),
          onSubmitted: (String _) => _submit(),
          style: OG.body(),
          decoration: InputDecoration(
            hintText: 'Search or add an exercise',
            filled: true,
            fillColor: OG.card,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 18,
            ),
            border: idle,
            enabledBorder: idle,
            focusedBorder: focused,
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: <Widget>[
              if (widget.options.isEmpty && typed.isEmpty)
                Text('No exercises in your log yet. Type a name to add one.', style: OG.muted()),
              for (final ExerciseOption o in matches)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OgButton(
                    shadow: false,
                    alignment: Alignment.centerLeft,
                    onPressed: () => _pick(o),
                    child: Text(o.name),
                  ),
                ),
              if (typed.isNotEmpty && _exact == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OgButton(
                    variant: OgVariant.accent,
                    alignment: Alignment.centerLeft,
                    onPressed: _submit,
                    child: Text('Add "${_newName(typed)}"'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The one question for a new name: sets and reps, or time.
class _MeasureQuestion extends StatelessWidget {
  const _MeasureQuestion({required this.name, required this.onChoose});

  final String name;
  final ValueChanged<bool> onChoose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('How do you track $name?', style: OG.body(weight: FontWeight.w700)),
        const SizedBox(height: 12),
        OgButton(
          variant: OgVariant.accent,
          onPressed: () => onChoose(false),
          child: const Text('Sets and reps'),
        ),
        const SizedBox(height: 10),
        OgButton(
          shadow: false,
          onPressed: () => onChoose(true),
          child: const Text('Time'),
        ),
      ],
    );
  }
}
