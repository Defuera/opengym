import 'package:flutter/material.dart';

import '../theme.dart';

class SegmentedToggle extends StatelessWidget {
  const SegmentedToggle({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final List<Widget> row = <Widget>[];
    for (int i = 0; i < labels.length; i++) {
      if (i > 0) {
        row.add(const SizedBox(width: 6));
      }
      final bool on = i == selectedIndex;
      row.add(Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(i),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? OG.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              labels[i],
              style: OG.body(
                weight: FontWeight.w600,
                color: on ? OG.white : OG.ink,
              ),
            ),
          ),
        ),
      ));
    }
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: OG.soft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: row),
    );
  }
}
