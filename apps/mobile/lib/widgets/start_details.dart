import 'package:flutter/material.dart';

import '../theme.dart';
import 'composer_bar.dart';
import 'og_button.dart';

/// Step 2 of the Start tab: the chosen type as title, one optional note and
/// "Start". A back arrow returns to the list. The note is typed in the shared
/// composer ([ComposerBar]); the button stays in view above the keyboard.
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Anything for today? (optional)',
                    style: OG.muted(size: 14, weight: FontWeight.w600)),
                const SizedBox(height: 6),
                // The same composer as every chat. The start request holds one text, so this
                // use has no files, no camera and no send button: "Start" is the action.
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ComposerBar(
                    key: const ValueKey<String>('start-note'),
                    controller: note,
                    maxLength: 2000,
                    hint: 'Short on time, go easy, left hand is sore…',
                  ),
                ),
              ],
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
