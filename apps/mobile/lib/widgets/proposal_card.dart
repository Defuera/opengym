import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';
import 'proposal_feedback.dart';
import 'sheet_link.dart';

/// The shared frame of "the coach proposes": the thing proposed ([child]), one
/// line of reason, a feedback box behind one tap, and (when [explicit]) the two
/// buttons Agree and Cancel. It knows nothing about what is proposed.
class ProposalCard extends StatefulWidget {
  const ProposalCard({
    super.key,
    required this.child,
    required this.feedback,
    this.reason = '',
    this.explicit = true,
    this.busy = false,
    this.busyText = 'The coach is rebuilding it…',
    this.error,
    this.online = true,
    this.agreeLabel = 'Agree',
    this.cancelLabel = 'Cancel',
    this.feedbackHint = 'Change something? Say what.',
    required this.onAgree,
    required this.onCancel,
    required this.onRebuild,
  });

  final Widget child;

  /// Owned by the caller, so typed text survives a rebuild of the screen.
  final TextEditingController feedback;
  final String reason;

  /// Whether the person must say yes. With false the buttons are not shown.
  final bool explicit;

  /// A rebuild runs: the buttons are off and a busy line shows.
  final bool busy;
  final String busyText;
  final String? error;
  final bool online;
  final String agreeLabel;
  final String cancelLabel;
  final String feedbackHint;
  final VoidCallback onAgree;
  final VoidCallback onCancel;

  /// Called with the trimmed feedback.
  final void Function(String feedback) onRebuild;

  @override
  State<ProposalCard> createState() => _ProposalCardState();
}

class _ProposalCardState extends State<ProposalCard> {
  bool _change = false;

  @override
  Widget build(BuildContext context) {
    final String? error = widget.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.reason.isNotEmpty) ...<Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: ogBox(color: OG.done, radius: 14, shadow: false),
            child: Text(widget.reason, style: OG.body(size: 15, weight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
        ],
        Opacity(opacity: widget.busy ? 0.4 : 1, child: widget.child),
        const SizedBox(height: 12),
        if (widget.busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: <Widget>[
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3, color: OG.ink)),
                const SizedBox(width: 12),
                Expanded(child: Text(widget.busyText, style: OG.body(size: 15, weight: FontWeight.w700))),
              ],
            ),
          ),
        if (error != null && error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(error, style: OG.body(size: 15, weight: FontWeight.w700, color: const Color(0xFFE5482D))),
          ),
        if (_change)
          ProposalFeedback(
            controller: widget.feedback,
            failed: false,
            online: widget.online && !widget.busy,
            hint: widget.feedbackHint,
            onRebuild: (String t) {
              setState(() => _change = false);
              widget.onRebuild(t);
            },
          )
        else if (!widget.busy)
          Align(
            alignment: Alignment.centerLeft,
            child: SheetLink(label: 'Change something', onTap: () => setState(() => _change = true)),
          ),
        if (widget.explicit) ...<Widget>[
          const SizedBox(height: 8),
          OgButton(
            key: const ValueKey<String>('proposal-agree'),
            variant: OgVariant.accent,
            onPressed: widget.busy ? null : widget.onAgree,
            child: Text(widget.agreeLabel),
          ),
          const SizedBox(height: 10),
          OgButton(
            key: const ValueKey<String>('proposal-cancel'),
            variant: OgVariant.dashed,
            onPressed: widget.onCancel,
            child: Text(widget.cancelLabel),
          ),
        ],
      ],
    );
  }
}
