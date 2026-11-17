import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'og_button.dart';
import 'og_icon_button.dart';

/// Bottom sheet to pick a library exercise or type a custom one.
/// Returns the chosen name (already trimmed), or null if dismissed.
Future<String?> showExercisePicker(
  BuildContext context, {
  required String title,
  required List<String> options,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: OG.ground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: OG.ink, width: 2),
    ),
    builder: (BuildContext ctx) => _PickerSheet(title: title, options: options),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.title, required this.options});

  final String title;
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
    final double keyboard = MediaQuery.of(context).viewInsets.bottom;
    final double maxH = MediaQuery.of(context).size.height * 0.82;
    final List<String> options = widget.options;

    final OutlineInputBorder idle = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: OG.ink, width: 2),
    );
    final OutlineInputBorder focused = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: OG.accent, width: 3),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OG.display(24),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OgIconButton(
                      icon: Icons.close,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
            ),
          ),
        ),
      ),
    );
  }
}
