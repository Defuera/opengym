import 'package:flutter/material.dart';

import '../theme.dart';

/// Small muted line under a section.
class Footnote extends StatelessWidget {
  const Footnote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
      child: Text(text, style: OG.muted(size: 12)),
    );
  }
}
