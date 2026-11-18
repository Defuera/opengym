import 'package:flutter/material.dart';

import '../theme.dart';

/// The coach's pick for today: a title, the reason (up to 3 lines) and a small
/// "Today" label. Information only: it does not react to taps. With no pick,
/// [title] is null and a short line shows instead.
class TodayCard extends StatelessWidget {
  const TodayCard({super.key, this.title, this.reason = ''});

  final String? title;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final String? t = title;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: ogBox(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Today', style: OG.muted(size: 14, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (t == null)
            Text('The coach picks a session for today.', style: OG.body())
          else ...<Widget>[
            Text(t,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: OG.display(24)),
            if (reason.isNotEmpty) ...<Widget>[
              const SizedBox(height: 3),
              Text(reason,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: OG.body(size: 16, color: OG.mute)),
            ],
          ],
        ],
      ),
    );
  }
}
