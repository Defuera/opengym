import 'package:flutter/material.dart';

import '../theme.dart';
import 'progress_bar.dart';

/// A goal with "current / target" and a progress bar.
class GoalProgressCard extends StatelessWidget {
  const GoalProgressCard({
    super.key,
    required this.title,
    required this.current,
    required this.target,
    required this.fraction,
  });

  final String title;
  final String current;
  final String target;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ogBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: OG.body(size: 18, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          ProgressBar(fraction: fraction),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Text(current, style: OG.body(weight: FontWeight.w700)),
              const Spacer(),
              Text('Target $target', style: OG.muted(size: 14)),
            ],
          ),
        ],
      ),
    );
  }
}
