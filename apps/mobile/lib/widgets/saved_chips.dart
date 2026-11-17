import 'package:flutter/material.dart';

import '../theme.dart';

/// "Saved to your context" with one small chip per saved item.
class SavedChips extends StatelessWidget {
  const SavedChips({super.key, required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Saved to your context', style: OG.muted(size: 13, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final String l in labels)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: OG.done,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: OG.ink, width: 2),
                ),
                child: Text(l, style: OG.body(size: 14, weight: FontWeight.w600)),
              ),
          ],
        ),
      ],
    );
  }
}
