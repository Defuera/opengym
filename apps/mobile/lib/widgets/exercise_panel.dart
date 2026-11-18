import 'package:flutter/material.dart';

import '../theme.dart';

/// The big card: title, optional hint, [pinned] widgets, then the children.
/// It has its own natural height and does not scroll: put it in a scroll view
/// so the whole card moves together and nothing slides under the title.
class ExercisePanel extends StatelessWidget {
  const ExercisePanel({
    super.key,
    required this.name,
    required this.children,
    this.hint,
    this.pinned = const <Widget>[],
  });

  final String name;
  final List<Widget> children;
  final String? hint;
  final List<Widget> pinned;

  @override
  Widget build(BuildContext context) {
    final String? h = hint;
    final List<Widget> body = <Widget>[
      Text(name, style: OG.display(28)),
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
      padding: const EdgeInsets.all(16),
      decoration: ogBox(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ...body,
          for (final Widget c in children) ...<Widget>[const SizedBox(height: 14), c],
        ],
      ),
    );
  }
}
