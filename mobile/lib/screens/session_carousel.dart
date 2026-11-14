import 'package:flutter/material.dart';

import '../models.dart';
import '../planner.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/dashed_box.dart';

const double _cardW = 150;
const double _gap = 10;
const double _pad = 20;

/// Horizontal exercise carousel with a trailing dashed "Add" card.
class ExerciseCarousel extends StatefulWidget {
  const ExerciseCarousel({super.key, required this.store, required this.onAdd});

  final AppStore store;
  final VoidCallback onAdd;

  @override
  State<ExerciseCarousel> createState() => _ExerciseCarouselState();
}

class _ExerciseCarouselState extends State<ExerciseCarousel> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(covariant ExerciseCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reveal();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Scroll so the current card is fully visible.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      final ScrollPosition pos = _controller.position;
      final double itemLeft = _pad + widget.store.curEx * (_cardW + _gap);
      final double itemRight = itemLeft + _cardW;
      final double viewLeft = pos.pixels;
      final double viewRight = viewLeft + pos.viewportDimension;
      double? dest;
      if (itemLeft - _pad < viewLeft) {
        dest = itemLeft - _pad;
      } else if (itemRight + _pad > viewRight) {
        dest = itemRight + _pad - pos.viewportDimension;
      }
      if (dest == null) {
        return;
      }
      final double clamped =
          dest.clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble();
      if ((clamped - pos.pixels).abs() < 1) {
        return;
      }
      _controller.animateTo(
        clamped,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppStore store = widget.store;
    final List<Exercise> list = store.active?.exercises ?? <Exercise>[];
    return SizedBox(
      height: 136,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(_pad, 2, _pad, 10),
        itemCount: list.length + 1,
        separatorBuilder: (BuildContext c, int i) => const SizedBox(width: _gap),
        itemBuilder: (BuildContext c, int i) {
          if (i == list.length) {
            return _AddCard(onTap: widget.onAdd);
          }
          return _ExerciseCard(
            exercise: list[i],
            index: i,
            current: i == store.curEx,
            store: store,
          );
        },
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.exercise,
    required this.index,
    required this.current,
    required this.store,
  });

  final Exercise exercise;
  final int index;
  final bool current;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final bool fin = allDone(exercise);
    final int doneCount = exercise.sets.where((SetEntry s) => s.done).length;
    final Color fg = current ? OG.white : OG.ink;
    final Color bg = current ? OG.ink : (fin ? OG.done : OG.card);
    return SizedBox(
      width: _cardW,
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
                  onTap: index == 0 ? null : () => store.moveExerciseEarlier(index),
                ),
                _Tool(
                  icon: Icons.close,
                  color: fg,
                  onTap: () => store.discardExercise(index),
                ),
              ],
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => store.pickExercise(index),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        exercise.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: OG.body(
                          size: 16,
                          weight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                      Text(
                        fin ? 'Done' : '$doneCount / ${exercise.sets.length} sets',
                        style: OG.body(size: 13, color: fg),
                      ),
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

class _AddCard extends StatelessWidget {
  const _AddCard({required this.onTap});

  final VoidCallback onTap;

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
              Text('Add', style: OG.body(size: 14, weight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

