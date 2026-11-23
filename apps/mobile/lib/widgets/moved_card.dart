import 'package:flutter/material.dart';

import '../theme.dart';

/// One exercise whose top set changed.
class MovedRow {
  const MovedRow({required this.name, required this.from, required this.to, required this.unit, required this.up});

  final String name;

  /// "20", "35" and "kg".
  final String from;
  final String to;
  final String unit;
  final bool up;

  /// "20 → 35 kg".
  String get change => '$from → $to $unit';
}

/// "What moved": one compact row per exercise.
class MovedCard extends StatelessWidget {
  const MovedCard({super.key, required this.rows});

  final List<MovedRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: ogBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('What moved', style: OG.muted(size: 14, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final MovedRow r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: <Widget>[
                Expanded(
                  child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: OG.body(size: 16, weight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Text(r.from, style: OG.body(size: 16)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.arrow_forward, size: 14, color: OG.mute),
                ),
                Text('${r.to} ${r.unit}', style: OG.body(size: 16, weight: FontWeight.w700)),
                const SizedBox(width: 6),
                Icon(
                  r.up ? Icons.arrow_upward : Icons.arrow_downward,
                  key: ValueKey<String>(r.up ? 'moved-up' : 'moved-down'),
                  size: 18,
                  color: r.up ? OG.accent : OG.mute,
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
