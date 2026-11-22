import 'package:flutter/material.dart';

import '../theme.dart';

/// One exercise of a finished session: its name and one line per entry.
class RecapExerciseCard extends StatelessWidget {
  const RecapExerciseCard({super.key, required this.name, required this.lines, this.comment});

  final String name;
  final List<String> lines;

  /// What the person wrote about the exercise in this session. Null: none.
  final String? comment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: ogBox(shadow: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(name, style: OG.body(size: 18, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (int i = 0; i < lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 28,
                    child: Text('${i + 1}', style: OG.muted(size: 15, weight: FontWeight.w700)),
                  ),
                  Expanded(child: Text(lines[i], style: OG.body(size: 17))),
                ],
              ),
            ),
          if (comment != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(comment!, key: const ValueKey<String>('recap-comment'), style: OG.muted(size: 15)),
            ),
        ],
      ),
    );
  }
}
