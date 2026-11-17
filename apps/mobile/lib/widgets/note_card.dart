import 'package:flutter/material.dart';

import '../theme.dart';

/// A plain note from the dashboard (filled, unlike the dashed NoteBox).
class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: ogBox(color: OG.done, shadow: false),
      child: Text(text, style: OG.body()),
    );
  }
}
