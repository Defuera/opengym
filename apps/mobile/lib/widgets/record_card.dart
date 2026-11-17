import 'package:flutter/material.dart';

import '../theme.dart';

/// One record: bold title (with its date) and a preview of the text.
class RecordCard extends StatelessWidget {
  const RecordCard({super.key, required this.title, required this.preview, required this.onTap});

  final String title;
  final String preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: ogBox(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: OG.body(size: 16, weight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis, style: OG.muted(size: 14)),
          ],
        ),
      ),
    );
  }
}
