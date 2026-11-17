import 'package:flutter/material.dart';

import '../theme.dart';

/// One square per day, oldest first. Filled means active.
class ConsistencyRow extends StatelessWidget {
  const ConsistencyRow({super.key, required this.title, required this.days});

  final String title;
  final List<bool> days;

  @override
  Widget build(BuildContext context) {
    final int active = days.where((bool d) => d).length;
    final bool dense = days.length > 10;
    final List<Widget> cells = <Widget>[];
    for (final bool on in days) {
      cells.add(Container(
        width: dense ? 18 : 30,
        height: dense ? 18 : 30,
        decoration: BoxDecoration(
          color: on ? OG.accent : OG.card,
          borderRadius: BorderRadius.circular(dense ? 5 : 8),
          border: Border.all(color: OG.ink, width: 2),
        ),
      ));
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ogBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(title, style: OG.body(size: 18, weight: FontWeight.w700)),
              ),
              Text('$active / ${days.length}', style: OG.muted()),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: cells),
        ],
      ),
    );
  }
}
