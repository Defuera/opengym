import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';

/// The big card: title with a Swap button, optional hint, [pinned] widgets,
/// then the children. Only the children scroll; the title and pinned part stay
/// in place, so nothing is cut at the top edge. Give it a bounded height
/// (e.g. inside Expanded).
class ExercisePanel extends StatelessWidget {
  const ExercisePanel({
    super.key,
    required this.name,
    required this.children,
    this.hint,
    this.pinned = const <Widget>[],
    this.onSwap,
    this.swapLabel = 'Swap',
  });

  final String name;
  final List<Widget> children;
  final String? hint;
  final List<Widget> pinned;
  final VoidCallback? onSwap;
  final String swapLabel;

  @override
  Widget build(BuildContext context) {
    final String? h = hint;
    final List<Widget> body = <Widget>[
      Row(
        children: <Widget>[
          Expanded(child: Text(name, style: OG.display(28))),
          const SizedBox(width: 12),
          OgButton(minHeight: 48, onPressed: onSwap, child: Text(swapLabel)),
        ],
      ),
    ];
    if (h != null) {
      body.add(const SizedBox(height: 6));
      body.add(Text(h, style: OG.muted(size: 14)));
    }
    for (final Widget c in pinned) {
      body.add(const SizedBox(height: 14));
      body.add(c);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: ogBox(radius: 20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: body),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final Widget c in children) ...<Widget>[const SizedBox(height: 14), c],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
