import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'og_button.dart';
import 'og_sheet.dart';

/// Bottom sheet to pick a library exercise or type a custom one.
/// Returns the chosen name (already trimmed), or null if dismissed.
Future<String?> showExercisePicker(
  BuildContext context, {
  required String title,
  required List<String> options,
}) {
  return showOgSheet<String>(
    context,
    (BuildContext ctx) => _PickerSheet(options: options),
    title: title,
    scroll: false,
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.options});

  final List<String> options;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _useCustom() {
    final String v = _controller.text.trim();
    if (v.isEmpty) {
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final List<String> options = widget.options;

    final OutlineInputBorder idle = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: OG.ink, width: 2),
    );
    final OutlineInputBorder focused = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: OG.accent, width: 3),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.done,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(40),
                ],
                onSubmitted: (String _) => _useCustom(),
                style: OG.body(),
                decoration: InputDecoration(
                  hintText: 'Other exercise',
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
            ),
            const SizedBox(width: 12),
            OgButton(
              onPressed: _useCustom,
              child: const Text('Use'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: <Widget>[
              for (final String n in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OgButton(
                    shadow: false,
                    alignment: Alignment.centerLeft,
                    onPressed: () => Navigator.of(context).pop(n),
                    child: Text(n),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
