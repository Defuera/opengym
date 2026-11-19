import 'package:flutter/material.dart';

import '../theme.dart';
import 'labeled_field.dart';
import 'og_button.dart';

/// The body of the "Change plan" sheet: one text field for what to change, a
/// "Rebuild" button, and a line when offline or after a failure. The caller
/// owns [controller], so typed text survives closing the sheet.
class ProposalFeedback extends StatelessWidget {
  const ProposalFeedback({
    super.key,
    required this.controller,
    required this.failed,
    required this.online,
    required this.onRebuild,
  });

  final TextEditingController controller;
  final bool failed;
  final bool online;

  /// Called with the trimmed text.
  final void Function(String feedback) onRebuild;

  void _send() {
    final String t = controller.text.trim();
    if (t.isNotEmpty) {
      FocusManager.instance.primaryFocus?.unfocus();
      onRebuild(t);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final bool can = online && controller.text.trim().isNotEmpty;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LabeledField(
              controller: controller,
              hint:
                  'Change something? For example: no water bottles, I have dumbbells',
              maxLength: 1000,
              maxLines: 4,
              minLines: 2,
              autocorrect: true,
              keyboardType: TextInputType.multiline,
            ),
            const SizedBox(height: 12),
            OgButton(
              variant: OgVariant.accent,
              onPressed: can ? _send : null,
              child: const Text('Rebuild'),
            ),
            if (!online)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    'Offline. You can rebuild when you are back online.',
                    style: OG.muted(size: 14)),
              ),
            if (failed && online)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Could not rebuild. Try again.',
                    style: OG.muted(size: 14)),
              ),
          ],
        );
      },
    );
  }
}
