import 'package:flutter/material.dart';

import '../theme.dart';
import 'dashed_box.dart';
import 'og_button.dart';

/// Dashed box with a free-text field and a small ink button ("Prepare",
/// "Log"). The button needs text; submitting the keyboard acts the same.
class SomethingNewBox extends StatelessWidget {
  const SomethingNewBox({
    super.key,
    required this.controller,
    required this.hint,
    required this.buttonLabel,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String hint;
  final String buttonLabel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return DashedBox(
      color: OG.card,
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: controller,
                maxLength: 2000,
                maxLines: 2,
                minLines: 1,
                textInputAction: TextInputAction.done,
                onSubmitted: (String _) => onSubmit(),
                style: OG.body(),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: OG.muted(),
                  counterText: '',
                  border: InputBorder.none,
                  isCollapsed: false,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OgButton(
              variant: OgVariant.ink,
              minHeight: 48,
              radius: 14,
              shadow: false,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              onPressed: onSubmit,
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
