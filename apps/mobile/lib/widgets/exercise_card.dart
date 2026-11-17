import 'package:flutter/material.dart';

import '../theme.dart';
import 'dashed_box.dart';
import 'item_state.dart';

/// One-line carousel chip: name, count such as "1 / 6", and a discard cross.
/// Reordering is done by long-press drag in [ExerciseCarousel].
class ExerciseCard extends StatelessWidget {
  const ExerciseCard({
    super.key,
    required this.name,
    required this.progressLabel,
    this.state = ItemState.idle,
    this.onTap,
    this.onDiscard,
    this.width = 220,
  });

  final String name;
  final String progressLabel;
  final ItemState state;
  final VoidCallback? onTap;
  final VoidCallback? onDiscard;
  final double width;

  @override
  Widget build(BuildContext context) {
    final bool current = state == ItemState.current;
    final Color fg = current ? OG.white : OG.ink;
    final Color sub = current ? const Color(0xFFCFCFCF) : OG.mute;
    final Color bg = current
        ? OG.ink
        : (state == ItemState.finished ? OG.done : OG.card);
    return SizedBox(
      width: width,
      height: 46,
      child: Container(
        decoration: ogBox(
          color: bg,
          offset: current ? 4 : 3,
          shadowColor: current ? OG.accent : OG.ink,
          radius: 14,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OG.body(size: 15, weight: FontWeight.w700, color: fg),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(progressLabel, style: OG.body(size: 13, color: sub)),
                    ],
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDiscard,
              child: SizedBox(
                width: 40,
                height: 44,
                child: Icon(Icons.close, size: 18, color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trailing dashed "Add" card for the carousel.
class AddCard extends StatelessWidget {
  const AddCard({super.key, required this.onTap, this.label = 'Add'});

  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 84,
        height: 46,
        child: DashedBox(
          radius: 14,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.add, size: 20),
              const SizedBox(width: 4),
              Text(label, style: OG.body(size: 14, weight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
