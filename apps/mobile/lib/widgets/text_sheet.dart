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
  bool allowEmpty = false,
  int maxLines = 1,
  int? maxLength,
  TextInputType? keyboardType,
}) {
  return showOgSheet<String>(
    context,
    (BuildContext ctx) => _TextSheet(
      label: label,
      actionLabel: actionLabel,
      hint: hint,
      initialText: initialText,
      allowEmpty: allowEmpty,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
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
    this.allowEmpty = false,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
  });

  final TextInputType? keyboardType;

  /// With this an empty text is an answer too (it clears the value).
  final bool allowEmpty;
  final int maxLines;
  final int? maxLength;

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
    if (v.isNotEmpty || widget.allowEmpty) {
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
          keyboardType: widget.keyboardType,
          maxLines: widget.maxLines,
          minLines: widget.maxLines > 1 ? 2 : null,
          maxLength: widget.maxLength,
          autocorrect: widget.maxLines > 1,
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
