import 'package:flutter/material.dart';

import 'chip_strip.dart';

/// A row of chips to pick the focus of a session ("Upper", "Legs", ...).
/// The advised focus is marked. [foci] is already ordered (advised first).
class FocusChips extends StatelessWidget {
  const FocusChips({
    super.key,
    required this.foci,
    required this.selected,
    required this.onSelect,
    this.advised,
  });

  final List<String> foci;

  /// The focus in use, or null when none is chosen yet.
  final String? selected;

  /// The advised focus: its chip says so.
  final String? advised;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ChipStrip(
      labels: <String>[
        for (final String f in foci) f == advised ? '$f · advised' : f,
      ],
      selectedIndex: selected == null ? -1 : foci.indexOf(selected!),
      onSelect: (int i) => onSelect(foci[i]),
    );
  }
}
