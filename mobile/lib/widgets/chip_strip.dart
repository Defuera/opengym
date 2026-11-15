import 'package:flutter/material.dart';

import 'og_chip.dart';

/// Horizontally scrolling chips with an optional "+" at the end.
class ChipStrip extends StatelessWidget {
  const ChipStrip({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelect,
    this.onAdd,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[];
    for (int i = 0; i < labels.length; i++) {
      items.add(OgChip(
        label: labels[i],
        selected: i == selectedIndex,
        onTap: () => onSelect(i),
      ));
      items.add(const SizedBox(width: 8));
    }
    if (onAdd != null) {
      items.add(OgChip(label: '+ New', selected: false, onTap: onAdd));
    }
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: items,
      ),
    );
  }
}
