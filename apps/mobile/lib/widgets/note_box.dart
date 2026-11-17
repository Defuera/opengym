import 'package:flutter/material.dart';

import '../theme.dart';
import 'dashed_box.dart';

/// Dashed empty-state note with a bold title and a muted message.
class NoteBox extends StatelessWidget {
  const NoteBox({
    super.key,
    required this.title,
    required this.message,
    this.centered = false,
  });

  final String title;
  final String message;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return DashedBox(
      radius: centered ? 20 : OG.radius,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        alignment: centered ? Alignment.center : Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: OG.body(weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: OG.muted(),
            ),
          ],
        ),
      ),
    );
  }
}
