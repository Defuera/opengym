import 'package:flutter/material.dart';

import '../theme.dart';

/// "This week": the session count, one square per day and a line about the
/// last session. [lines] are extra muted lines (the month figures).
class WeekCard extends StatelessWidget {
  const WeekCard({
    super.key,
    required this.title,
    required this.headline,
    required this.days,
    this.dayLetters = const <String>[],
    this.lines = const <String>[],
    this.last,
  });

  final String title;

  /// "5 of 5 sessions".
  final String headline;

  /// Oldest first. Filled means a session that day.
  final List<bool> days;

  /// One letter under each square. Empty: none.
  final List<String> dayLetters;
  final List<String> lines;

  /// "Last: yesterday, Gym, Legs". Null hides the line.
  final String? last;

  @override
  Widget build(BuildContext context) {
    final bool dense = days.length > 10;
    final bool letters = dayLetters.length == days.length && !dense;
    final List<Widget> cells = <Widget>[];
    for (int i = 0; i < days.length; i++) {
      final Widget square = Container(
        width: dense ? 18 : 34,
        height: dense ? 18 : 34,
        decoration: BoxDecoration(
          color: days[i] ? OG.accent : OG.card,
          borderRadius: BorderRadius.circular(dense ? 5 : 8),
          border: Border.all(color: OG.ink, width: 2),
        ),
      );
      cells.add(letters
          ? Column(children: <Widget>[
              square,
              const SizedBox(height: 4),
              Text(dayLetters[i], style: OG.muted(size: 12, weight: FontWeight.w600)),
            ])
          : square);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: ogBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: OG.muted(size: 14, weight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(headline, style: OG.display(28)),
          const SizedBox(height: 12),
          if (dense)
            Wrap(spacing: 6, runSpacing: 6, children: cells)
          else
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: cells),
          for (final String l in lines) ...<Widget>[
            const SizedBox(height: 8),
            Text(l, style: OG.muted(size: 15)),
          ],
          if (last != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(last!, key: const ValueKey<String>('week-last'), style: OG.body(size: 16, weight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}
