import 'package:flutter/material.dart';

import '../theme.dart';
import 'session_meta_row.dart';

/// The compact lines under a coach reply: one per function the coach ran.
class ActionLines extends StatelessWidget {
  const ActionLines({super.key, required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final String l in lines)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(Icons.subdirectory_arrow_right, size: 15, color: OG.mute),
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(l, style: OG.muted(size: 14, weight: FontWeight.w600))),
              ],
            ),
          ),
      ],
    );
  }
}

/// A whole-workout proposal: a compact list, one row per exercise.
class PlanList extends StatelessWidget {
  const PlanList({super.key, this.title, required this.rows});

  final String? title;

  /// (exercise name, short sets text)
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('coach-proposal'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: ogBox(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Text(title!, style: OG.body(weight: FontWeight.w700)),
            const SizedBox(height: 8),
          ],
          for (final (String, String) r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: Text(r.$1, style: OG.body(size: 15, weight: FontWeight.w600))),
                  const SizedBox(width: 12),
                  Text(r.$2, style: OG.muted(size: 14)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A question of the coach as text, with a quick-answer button per answer.
/// [onAnswer] gets the label. [enabled] false while a send runs.
class QuestionBlock extends StatelessWidget {
  const QuestionBlock({
    super.key,
    required this.text,
    required this.answers,
    required this.onAnswer,
    this.enabled = true,
  });

  final String text;
  /// (id, label)
  final List<(String, String)> answers;
  final void Function(String id, String label) onAnswer;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(text, style: OG.body(weight: FontWeight.w600)),
        if (answers.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final (String, String) a in answers)
                MetaItem(label: a.$2, onTap: () => enabled ? onAnswer(a.$1, a.$2) : null),
            ],
          ),
        ],
      ],
    );
  }
}

/// The small line at the top of a chat that was opened with a context.
class ContextLine extends StatelessWidget {
  const ContextLine({super.key, required this.text, this.place});

  final String text;

  /// The place of the open session, shown after the text with a location icon. Null or empty: nothing extra.
  final String? place;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('chat-context'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: metaChipBox(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.push_pin_outlined, size: 15, color: OG.ink),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: OG.body(size: 14, weight: FontWeight.w600)),
          ),
          if (place != null && place!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(width: 10),
            const Icon(Icons.place_outlined, size: 15, color: OG.mute),
            const SizedBox(width: 3),
            ConstrainedBox(
              key: const ValueKey<String>('chat-context-place'),
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(place!.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: OG.body(size: 14, weight: FontWeight.w600, color: OG.mute)),
            ),
          ],
        ],
      ),
    );
  }
}
