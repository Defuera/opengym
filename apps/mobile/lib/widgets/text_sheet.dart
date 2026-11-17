import 'package:flutter/material.dart';

import '../theme.dart';
import 'labeled_field.dart';
import 'og_button.dart';

/// Bottom sheet with one text field. Returns the trimmed text, or null.
Future<String?> showTextSheet(
  BuildContext context, {
  required String title,
  required String label,
  required String actionLabel,
  String? hint,
  String? initialText,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: OG.ground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: OG.ink, width: 2),
    ),
    builder: (BuildContext ctx) => _TextSheet(
      title: title,
      label: label,
      actionLabel: actionLabel,
      hint: hint,
      initialText: initialText,
    ),
  );
}

class _TextSheet extends StatefulWidget {
  const _TextSheet({
    required this.title,
    required this.label,
    required this.actionLabel,
    this.hint,
    this.initialText,
  });

  final String title;
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
    final double keyboard = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 12 + keyboard),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(widget.title, style: OG.display(24)),
            const SizedBox(height: 14),
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
        ),
      ),
    );
  }
}
