import 'package:flutter/material.dart';

import 'labeled_field.dart';
import 'og_button.dart';
import 'start_details.dart';

/// "Something else" in the Start tab: one free text (max 200) that says what the user
/// wants to do, and "Start". The coach names the activity and builds the
/// session. "Start" stays off while the text is empty.
class StartOther extends StatelessWidget {
  const StartOther({
    super.key,
    required this.text,
    required this.onBack,
    required this.onStart,
  });

  final TextEditingController text;
  final VoidCallback onBack;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        StartStepHeader(title: 'Something else', onBack: onBack),
        const SizedBox(height: 8),
        Flexible(
          child: SingleChildScrollView(
            child: LabeledField(
              label: 'What do you want to do?',
              controller: text,
              hint: 'quick home session, 15 min',
              maxLength: 200,
              minLines: 2,
              maxLines: 4,
              autocorrect: true,
              keyboardType: TextInputType.multiline,
            ),
          ),
        ),
        const SizedBox(height: 14),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: text,
          builder: (BuildContext context, TextEditingValue v, Widget? child) {
            return OgButton(
              variant: OgVariant.accent,
              onPressed: v.text.trim().isEmpty ? null : onStart,
              child: const Text('Start'),
            );
          },
        ),
      ],
    );
  }
}
