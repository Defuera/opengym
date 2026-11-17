import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';
import 'progress_bar.dart';

/// One import: progress while running, counts and notes when finished, and an
/// "Undo this import" button.
class ImportJobCard extends StatelessWidget {
  const ImportJobCard({
    super.key,
    required this.title,
    required this.processed,
    required this.total,
    required this.running,
    required this.summary,
    this.notes = const <String>[],
    this.onUndo,
  });

  final String title;
  final int processed;
  final int total;
  final bool running;

  /// e.g. "3 sessions, 1 goal, 2 notes saved".
  final String summary;
  final List<String> notes;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final List<Widget> kids = <Widget>[
      Text(title, style: OG.body(size: 18, weight: FontWeight.w700)),
      const SizedBox(height: 8),
    ];
    if (running) {
      kids.add(ProgressBar(fraction: total == 0 ? null : processed / total));
      kids.add(const SizedBox(height: 6));
      kids.add(Text('$processed of $total processed', style: OG.muted(size: 14)));
    } else {
      kids.add(Text(summary, style: OG.body()));
      for (final String n in notes) {
        kids.add(const SizedBox(height: 4));
        kids.add(Text(n, style: OG.muted(size: 14)));
      }
    }
    final VoidCallback? undo = onUndo;
    if (undo != null && !running) {
      kids.add(const SizedBox(height: 12));
      kids.add(OgButton(
        minHeight: 48,
        onPressed: undo,
        child: const Text('Undo this import'),
      ));
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ogBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: kids,
      ),
    );
  }
}
