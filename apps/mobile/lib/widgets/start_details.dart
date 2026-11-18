import 'package:flutter/material.dart';

import '../theme.dart';
import 'labeled_field.dart';
import 'og_button.dart';

/// Step 2 of the Start tab: the chosen type as title, one optional note and
/// "Start". A back arrow returns to the list. The note scrolls; the button
/// stays in view above the keyboard.
class StartDetails extends StatelessWidget {
  const StartDetails({
    super.key,
    required this.title,
    required this.note,
    required this.onBack,
    required this.onStart,
  });

  final String title;
  final TextEditingController note;
  final VoidCallback onBack;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        StartStepHeader(title: title, onBack: onBack),
        const SizedBox(height: 8),
        Flexible(
          child: SingleChildScrollView(
            child: LabeledField(
              label: 'Anything for today? (optional)',
              controller: note,
              hint: 'Short on time, go easy, left hand is sore…',
              maxLength: 200,
              minLines: 2,
              maxLines: 4,
              autocorrect: true,
              keyboardType: TextInputType.multiline,
            ),
          ),
        ),
        const SizedBox(height: 14),
        OgButton(
          variant: OgVariant.accent,
          onPressed: onStart,
          child: const Text('Start'),
        ),
      ],
    );
  }
}

/// A back arrow and a one-line title: the top of step 2 and of the Other form.
class StartStepHeader extends StatelessWidget {
  const StartStepHeader({super.key, required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: 'Back',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: OG.ink),
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OG.display(24),
          ),
        ),
      ],
    );
  }
}
