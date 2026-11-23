import 'package:flutter/material.dart';

import '../theme.dart';
import 'progress_bar.dart';

/// "Road to": a goal with a date. The bar shows the time gone from the day
/// the goal was set to its date. [progress] adds real progress when the goal
/// has a number and a current value.
class RoadCard extends StatelessWidget {
  const RoadCard({
    super.key,
    required this.title,
    required this.daysLeft,
    required this.elapsed,
    required this.sessionsText,
    this.progress,
    this.progressCurrent,
    this.progressTarget,
  });

  final String title;

  /// "26 days left".
  final String daysLeft;

  /// 0..1, time gone.
  final double elapsed;

  /// "9 sessions so far".
  final String sessionsText;
  final double? progress;
  final String? progressCurrent;
  final String? progressTarget;

  @override
  Widget build(BuildContext context) {
    final double? p = progress;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: ogBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Road to', style: OG.muted(size: 14, weight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(title, style: OG.body(size: 18, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          ProgressBar(fraction: elapsed, height: 14),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Text(daysLeft, key: const ValueKey<String>('road-days'), style: OG.body(weight: FontWeight.w700)),
              const Spacer(),
              Flexible(child: Text(sessionsText, style: OG.muted(size: 14), textAlign: TextAlign.right)),
            ],
          ),
          if (p != null) ...<Widget>[
            const SizedBox(height: 12),
            ProgressBar(fraction: p, height: 14),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Text(progressCurrent ?? '', style: OG.body(weight: FontWeight.w700)),
                const Spacer(),
                Text('Target ${progressTarget ?? ''}', style: OG.muted(size: 14)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
