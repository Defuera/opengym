import 'package:flutter/material.dart';

import '../theme.dart';

/// A goal in the list: title, detail line, done toggle and delete.
class GoalRow extends StatelessWidget {
  const GoalRow({
    super.key,
    required this.title,
    required this.detail,
    required this.done,
    required this.onToggleDone,
    required this.onDelete,
    this.onTap,
  });

  final String title;
  final String detail;
  final bool done;
  final VoidCallback onToggleDone;
  final VoidCallback onDelete;

  /// Tap on the text: edit the goal.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: ogBox(color: done ? OG.done : OG.card, shadow: false),
      child: Row(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleDone,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Center(
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: done ? OG.ink : OG.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: OG.ink, width: 2),
                  ),
                  child: done ? const Icon(Icons.check, size: 22, color: OG.white) : null,
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: OG.body(size: 18, weight: FontWeight.w700).copyWith(
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                  ),
                  if (detail.isNotEmpty) Text(detail, style: OG.muted(size: 14)),
                ],
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDelete,
            child: const SizedBox(
              width: 52,
              height: 52,
              child: Icon(Icons.delete_outline, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}
