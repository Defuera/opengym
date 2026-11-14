import 'package:flutter/material.dart';

import '../theme.dart';
import 'dashed_box.dart';
import 'item_state.dart';

/// One set: small label (with optional tick) over a value like "6×60".
/// Takes the width its parent gives it (see [SetGrid]).
class SetTile extends StatelessWidget {
  const SetTile({
    super.key,
    required this.label,
    required this.value,
    this.state = ItemState.idle,
    this.checked = false,
    this.onTap,
  });

  final String label;
  final String value;
  final ItemState state;
  final bool checked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool current = state == ItemState.current;
    final Color fg = current ? OG.white : OG.ink;
    final Color bg = current
        ? OG.ink
        : (state == ItemState.finished ? OG.done : OG.card);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 62,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OG.ink, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OG.body(size: 12, weight: FontWeight.w600, color: fg),
                  ),
                ),
                Text(
                  checked ? '✓' : '',
                  style: OG.body(size: 12, weight: FontWeight.w600, color: fg),
                ),
              ],
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: OG.display(17, color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashed action tile such as "+ Set".
class ToolTile extends StatelessWidget {
  const ToolTile({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 62,
        child: DashedBox(
          radius: 12,
          child: Center(
            child: Text(label, style: OG.body(size: 14, weight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

/// Lays children out four per row with 8px gaps.
class SetGrid extends StatelessWidget {
  const SetGrid({super.key, required this.children, this.columns = 4});

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double w =
            ((box.maxWidth - 8 * (columns - 1)) / columns).floorToDouble();
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final Widget c in children) SizedBox(width: w, child: c),
          ],
        );
      },
    );
  }
}
