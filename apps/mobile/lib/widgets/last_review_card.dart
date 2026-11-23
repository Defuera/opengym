import 'package:flutter/material.dart';

import '../theme.dart';

/// "Last review": the coach's words on the latest reviewed session, at most
/// three lines. A tap opens the session.
class LastReviewCard extends StatelessWidget {
  const LastReviewCard({super.key, required this.session, required this.summary, this.onTap});

  /// "Gym, Legs · yesterday".
  final String session;
  final String summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: ogBox(color: OG.done),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Last review', style: OG.muted(size: 14, weight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(session, style: OG.body(size: 17, weight: FontWeight.w700), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text(summary, maxLines: 3, overflow: TextOverflow.ellipsis, style: OG.body(size: 16)),
          ],
        ),
      ),
    );
  }
}
