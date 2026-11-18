import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_icon_button.dart';

/// Dismissible summary of the session that was just finished.
class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.summary,
    required this.changes,
    this.onDismiss,
    this.title = 'Last session',
  });

  final String summary;
  final List<String> changes;
  /// Null hides the close button (the card is part of a screen, not a banner).
  final VoidCallback? onDismiss;
  final String title;

  @override
  Widget build(BuildContext context) {
    final List<Widget> lines = <Widget>[];
    for (final String c in changes) {
      lines.add(const SizedBox(height: 6));
      lines.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('•  ', style: OG.body(weight: FontWeight.w700)),
          Expanded(child: Text(c, style: OG.body(size: 16))),
        ],
      ));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
      decoration: ogBox(color: OG.done),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: OG.muted(size: 14, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(summary, style: OG.body(weight: FontWeight.w600)),
                ...lines,
              ],
            ),
          ),
          if (onDismiss != null) ...<Widget>[
            const SizedBox(width: 8),
            OgIconButton(icon: Icons.close, onPressed: onDismiss!),
          ],
        ],
      ),
    );
  }
}
