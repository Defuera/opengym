import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';

/// The log the coach drafted, as a card in the chat (ADR-032). It has the same
/// frame as the whole-workout list ([PlanList]): kind, summary, time, then one
/// compact labelled row for each part the draft holds. The buttons are not
/// here: the chat shows the question under the card, as for any proposal.
///
/// [state] is open | applied | stale. An applied card carries a "Logged" mark;
/// a stale card is grey.
class LogDraftCard extends StatelessWidget {
  const LogDraftCard({
    super.key,
    required this.kind,
    this.color,
    required this.summary,
    required this.when,
    this.rows = const <(String, String)>[],
    this.exercises = const <(String, String)>[],
    this.state = 'open',
  });

  /// "Meal", "Training", "Body", "Goal" or "Note".
  final String kind;

  /// The category colour from the server. Null: the muted grey.
  final Color? color;
  final String summary;

  /// "Today, 19:30".
  final String when;

  /// (label, value) for the session, goal, limit and note parts, in order.
  final List<(String, String)> rows;

  /// (exercise name, short sets text), shown under the session row.
  final List<(String, String)> exercises;
  final String state;

  @override
  Widget build(BuildContext context) {
    final bool applied = state == 'applied';
    final bool stale = state == 'stale';
    return Opacity(
      opacity: stale ? 0.5 : 1,
      child: Container(
        key: const ValueKey<String>('log-draft'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: ogBox(radius: 16, color: stale ? OG.soft : OG.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(kind, key: const ValueKey<String>('log-draft-kind'), style: OG.body(size: 14, weight: FontWeight.w700, color: color ?? OG.mute)),
                const Spacer(),
                if (applied)
                  Row(
                    key: const ValueKey<String>('log-draft-logged'),
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.check, size: 16, color: OG.ink),
                      const SizedBox(width: 4),
                      Text('Logged', style: OG.body(size: 14, weight: FontWeight.w700)),
                    ],
                  ),
                if (stale) Text('Replaced', style: OG.muted(size: 14, weight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(summary, style: OG.body(weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(when, key: const ValueKey<String>('log-draft-when'), style: OG.muted(size: 14)),
            const SizedBox(height: 8),
            for (final (String, String) r in rows) ...<Widget>[
              _Row(label: r.$1, value: r.$2),
              if (r.$1 == 'Session')
                for (final (String, String) e in exercises)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: Text(e.$1, style: OG.body(size: 15, weight: FontWeight.w600))),
                        const SizedBox(width: 12),
                        Text(e.$2, style: OG.muted(size: 14)),
                      ],
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 64, child: Text(label, style: OG.muted(size: 14, weight: FontWeight.w600))),
          Expanded(child: Text(value, style: OG.body(size: 15, weight: FontWeight.w600))),
        ],
      ),
    );
  }
}

/// The end of a log chat: "Logged" and two actions. Close goes back to where
/// the person came from; Open shows the entry.
class LogEndLine extends StatelessWidget {
  const LogEndLine({super.key, required this.onClose, required this.onOpen});

  final VoidCallback onClose;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('log-end'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.check_circle_outline, size: 20, color: OG.ink),
            const SizedBox(width: 8),
            Text('Logged', style: OG.body(weight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: OgButton(
                key: const ValueKey<String>('log-close'),
                variant: OgVariant.dashed,
                minHeight: 48,
                onPressed: onClose,
                child: const Text('Close'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OgButton(
                key: const ValueKey<String>('log-open'),
                variant: OgVariant.accent,
                minHeight: 48,
                onPressed: onOpen,
                child: const Text('Open'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
