import 'package:flutter/material.dart';

/// Horizontal strip of fixed-width cards. Long-press a card and drag to reorder
/// ([onReorder] gets the old index and the final new index). Owns its scroll
/// controller and keeps the selected card in view. [footer] (e.g. an Add card)
/// is not reorderable. Every child needs a unique, stable key.
class ExerciseCarousel extends StatefulWidget {
  const ExerciseCarousel({
    super.key,
    required this.children,
    required this.selectedIndex,
    this.onReorder,
    this.footer,
    this.itemWidth = 220,
    this.gap = 10,
    this.height = 64,
    this.endPad = 20,
  });

  /// The space after the last card.
  final double endPad;

  final void Function(int from, int to)? onReorder;
  final Widget? footer;

  final List<Widget> children;
  final int selectedIndex;
  final double itemWidth;
  final double gap;
  final double height;

  @override
  State<ExerciseCarousel> createState() => _ExerciseCarouselState();
}

class _ExerciseCarouselState extends State<ExerciseCarousel> {
  static const double _pad = 20;

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

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      final ScrollPosition pos = _controller.position;
      final double itemLeft =
          _pad + widget.selectedIndex * (widget.itemWidth + widget.gap);
      final double itemRight = itemLeft + widget.itemWidth;
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
    final Widget? footer = widget.footer;
    return SizedBox(
      height: widget.height,
      child: ReorderableListView(
        scrollController: _controller,
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        padding: EdgeInsets.fromLTRB(_pad, 2, widget.endPad, 10),
        footer: footer,
        proxyDecorator: (Widget child, int index, Animation<double> a) =>
            Material(type: MaterialType.transparency, child: child),
        onReorderItem: (int from, int to) => widget.onReorder?.call(from, to),
        children: <Widget>[
          for (int i = 0; i < widget.children.length; i++)
            ReorderableDelayedDragStartListener(
              key: widget.children[i].key,
              index: i,
              enabled: widget.onReorder != null,
              child: Padding(
                padding: EdgeInsets.only(right: widget.gap),
                child: widget.children[i],
              ),
            ),
        ],
      ),
    );
  }
}
