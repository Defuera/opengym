import 'package:flutter/material.dart';

import '../theme.dart';
import 'dashed_box.dart';
import 'item_state.dart';

/// Carousel card: move-earlier arrow, discard cross, name and progress.
class ExerciseCard extends StatelessWidget {
  const ExerciseCard({
    super.key,
    required this.name,
    required this.progressLabel,
    this.state = ItemState.idle,
    this.canMoveEarlier = true,
    this.onTap,
    this.onMoveEarlier,
    this.onDiscard,
    this.width = 150,
  });

  final String name;
  final String progressLabel;
  final ItemState state;
  final bool canMoveEarlier;
  final VoidCallback? onTap;
  final VoidCallback? onMoveEarlier;
  final VoidCallback? onDiscard;
  final double width;

  @override
  Widget build(BuildContext context) {
    final bool current = state == ItemState.current;
    final Color fg = current ? OG.white : OG.ink;
    final Color bg = current
        ? OG.ink
        : (state == ItemState.finished ? OG.done : OG.card);
    return SizedBox(
      width: width,
      child: Container(
        decoration: ogBox(
          color: bg,
          offset: current ? 4 : 3,
          shadowColor: current ? OG.accent : OG.ink,
        ),
        child: Column(
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _Tool(
                  icon: Icons.chevron_left,
                  color: fg,
                  onTap: canMoveEarlier ? onMoveEarlier : null,
                ),
                _Tool(icon: Icons.close, color: fg, onTap: onDiscard),
              ],
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: OG.body(size: 16, weight: FontWeight.w700, color: fg),
                      ),
                      Text(progressLabel, style: OG.body(size: 13, color: fg)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.25 : 1,
        child: SizedBox(
          width: 44,
          height: 40,
          child: Icon(icon, size: 22, color: color),
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
        child: DashedBox(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.add, size: 26),
              const SizedBox(height: 4),
              Text(label, style: OG.body(size: 14, weight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
