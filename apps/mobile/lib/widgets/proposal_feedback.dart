import 'package:flutter/material.dart';

import '../theme.dart';
import 'labeled_field.dart';
import 'og_button.dart';
import 'preparing_card.dart';

/// Under a proposed session: one text field for what to change and a
/// "Rebuild" button. While the coach rebuilds it shows the preparing card.
/// The field is cleared after a rebuild went through and kept after a failure.
class ProposalFeedback extends StatefulWidget {
  const ProposalFeedback({
    super.key,
    required this.busy,
    required this.failed,
    required this.online,
    required this.onRebuild,
    required this.onKeep,
  });

  final bool busy;
  final bool failed;
  final bool online;

  /// Called with the trimmed text.
  final void Function(String feedback) onRebuild;

  /// Stops waiting and keeps the shown proposal.
  final VoidCallback onKeep;

  @override
  State<ProposalFeedback> createState() => _ProposalFeedbackState();
}

class _ProposalFeedbackState extends State<ProposalFeedback> {
  final TextEditingController _text = TextEditingController();

  @override
  void didUpdateWidget(ProposalFeedback old) {
    super.didUpdateWidget(old);
    if (old.busy && !widget.busy && !widget.failed) {
      _text.clear();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final String t = _text.text.trim();
    if (t.isNotEmpty) {
      FocusManager.instance.primaryFocus?.unfocus();
      widget.onRebuild(t);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.busy) {
      return PreparingCard(
        title: 'Rebuilding…',
        message: 'The coach changes the session with your feedback.',
        actionLabel: 'Keep this session',
        onAction: widget.onKeep,
      );
    }
    return ListenableBuilder(
      listenable: _text,
      builder: (BuildContext context, Widget? child) {
        final bool can = widget.online && _text.text.trim().isNotEmpty;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: LabeledField(
                    controller: _text,
                    hint: 'Change something? For example: no water bottles, I have dumbbells',
                    maxLength: 300,
                    maxLines: 3,
                    minLines: 1,
                    autocorrect: true,
                    keyboardType: TextInputType.multiline,
                  ),
                ),
                const SizedBox(width: 10),
                OgButton(
                  onPressed: can ? _send : null,
                  child: const Text('Rebuild'),
                ),
              ],
            ),
            if (!widget.online)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Offline. You can rebuild when you are back online.', style: OG.muted(size: 14)),
              ),
            if (widget.failed && widget.online)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Could not rebuild. Try again.', style: OG.muted(size: 14)),
              ),
          ],
        );
      },
    );
  }
}
