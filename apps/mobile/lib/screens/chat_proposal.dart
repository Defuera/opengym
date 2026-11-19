import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/proposal_card.dart';
import '../widgets/sheet_link.dart';
import 'program_text.dart';

/// The proposal of the coach under a chat message: a busy line while the
/// program is written, the program with Agree and Cancel when it is ready,
/// and one quiet line for each end state. Feedback is the next chat message,
/// so there is no feedback box here.
class ChatProposal extends StatelessWidget {
  const ChatProposal({
    super.key,
    required this.proposal,
    required this.live,
    required this.busy,
    required this.onAgree,
    required this.onCancel,
    this.programId,
    this.onOpenProgram,
  });

  /// Null: the server has no such proposal (removed after a while). Nothing shows.
  final Proposal? proposal;

  /// True only for the newest ready proposal of the chat.
  final bool live;

  /// Agree or Cancel is running.
  final bool busy;
  final VoidCallback onAgree;
  final VoidCallback onCancel;

  /// The program of an agreed proposal, for the "Open program" link.
  final String? programId;
  final void Function(String programId)? onOpenProgram;

  Widget _line(String text, {Color? color, bool muted = false, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              text,
              style: muted
                  ? OG.muted(size: 15)
                  : color == null
                      ? OG.body(size: 15, weight: FontWeight.w700)
                      : OG.body(size: 15, weight: FontWeight.w700, color: color),
            ),
          ),
          if (trailing != null) ...<Widget>[const SizedBox(width: 12), trailing],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Proposal? p = proposal;
    if (p == null) {
      return const SizedBox.shrink();
    }
    switch (p.status) {
      case 'building':
        return Container(
          key: const ValueKey<String>('proposal-building'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: ogBox(color: OG.done, radius: 14, shadow: false),
          child: Row(
            children: <Widget>[
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3, color: OG.ink)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'The coach is writing the program. This can take a minute or two.',
                  style: OG.body(size: 15, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      case 'ready':
        final Program? value = p.program;
        if (!live) {
          return _line('Replaced or cancelled', muted: true);
        }
        if (value == null) {
          return const SizedBox.shrink();
        }
        return ProposalCard(
          key: ValueKey<String>('proposal-${p.proposalId}'),
          reason: p.reason,
          explicit: p.explicit,
          busy: busy,
          busyText: 'Working…',
          onAgree: onAgree,
          onCancel: onCancel,
          child: programView(value),
        );
      case 'applied':
        final String? id = programId ?? p.targetId;
        final void Function(String)? open = onOpenProgram;
        return _line(
          'Agreed',
          trailing: id == null || open == null
              ? null
              : SheetLink(label: 'Open program', onTap: () => open(id)),
        );
      case 'declined':
        return _line('Replaced or cancelled', muted: true);
      case 'stale':
        return _line('The program changed. Ask again.', muted: true);
      case 'failed':
        final String e = p.error ?? '';
        return _line(e.isEmpty ? 'The coach could not write the program.' : e, color: const Color(0xFFE5482D));
    }
    return const SizedBox.shrink();
  }
}
