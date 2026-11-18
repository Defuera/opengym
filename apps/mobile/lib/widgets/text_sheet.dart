import 'package:flutter/material.dart';

import 'labeled_field.dart';
import 'og_button.dart';
import 'og_sheet.dart';

/// Bottom sheet with one text field. Returns the trimmed text, or null.
Future<String?> showTextSheet(
  BuildContext context, {
  required String title,
  required String label,
  required String actionLabel,
  String? hint,
  String? initialText,
}) {
  return showOgSheet<String>(
    context,
    (BuildContext ctx) => _TextSheet(
      label: label,
      actionLabel: actionLabel,
      hint: hint,
      initialText: initialText,
    ),
    title: title,
  );
}

class _TextSheet extends StatefulWidget {
  const _TextSheet({
    required this.label,
    required this.actionLabel,
    this.hint,
    this.initialText,
  });

  final String label;
  final String actionLabel;
  final String? hint;
  final String? initialText;

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late final TextEditingController _c = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() {
    final String v = _c.text.trim();
    if (v.isNotEmpty) {
      FocusManager.instance.primaryFocus?.unfocus(); // the keyboard closes with the sheet
      Navigator.of(context).pop(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LabeledField(
          label: widget.label,
          controller: _c,
          hint: widget.hint,
          onSubmitted: (String v) => _done(),
        ),
        const SizedBox(height: 14),
        OgButton(
          variant: OgVariant.accent,
          onPressed: _done,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
