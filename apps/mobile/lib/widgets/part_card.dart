import 'package:flutter/material.dart';

import '../theme.dart';
import 'status_pill.dart';

/// The card under the figure for the tapped part: its name, a status pill
/// (only for a limit), a line of words and one action link.
class PartCard extends StatelessWidget {
  const PartCard({
    super.key,
    required this.title,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.status,
    this.statusLabel,
  });

  final String title;
  final String text;
  /// Null: the card has no action link.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// active | improving | cleared, or null for a plain muscle.
  final String? status;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: ogBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(title, style: OG.display(20))),
              if (status != null)
                StatusPill(label: statusLabel ?? '', status: status!, red: status == 'active'),
            ],
          ),
          if (text.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(text, style: OG.muted(size: 14)),
          ],
          if (actionLabel != null)
          GestureDetector(
            key: const ValueKey<String>('part-action'),
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.centerLeft,
              child: Text(actionLabel!, style: OG.body(size: 14, weight: FontWeight.w800, color: OG.accent)),
            ),
          ),
        ],
      ),
    );
  }
}
