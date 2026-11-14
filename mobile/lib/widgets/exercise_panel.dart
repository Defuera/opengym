import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';

/// The big card: title with a Swap button, optional hint, then the children.
/// Scrolls internally, so give it a bounded height (e.g. inside Expanded).
class ExercisePanel extends StatelessWidget {
  const ExercisePanel({
    super.key,
    required this.name,
    required this.children,
    this.hint,
    this.onSwap,
    this.swapLabel = 'Swap',
  });

  final String name;
  final List<Widget> children;
  final String? hint;
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
    for (final Widget c in children) {
      body.add(const SizedBox(height: 14));
      body.add(c);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: ogBox(radius: 20),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: body,
        ),
      ),
    );
  }
}
