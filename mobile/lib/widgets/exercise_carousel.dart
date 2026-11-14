import 'package:flutter/material.dart';

/// Horizontal strip of fixed-width cards. Owns its scroll controller and keeps
/// the selected card in view. The last child may be narrower (e.g. an Add card).
class ExerciseCarousel extends StatefulWidget {
  const ExerciseCarousel({
    super.key,
    required this.children,
    required this.selectedIndex,
    this.itemWidth = 150,
    this.gap = 10,
    this.height = 136,
  });

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
    return SizedBox(
      height: widget.height,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(_pad, 2, _pad, 10),
        itemCount: widget.children.length,
        separatorBuilder: (BuildContext c, int i) => SizedBox(width: widget.gap),
        itemBuilder: (BuildContext c, int i) => widget.children[i],
      ),
    );
  }
}
