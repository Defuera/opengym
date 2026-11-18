import 'package:flutter/material.dart';

import '../theme.dart';

/// Row for a note: bold first line, muted time, a small paperclip with the
/// number of attached files. Tap opens the note.
class EntryListItem extends StatelessWidget {
  const EntryListItem({
    super.key,
    required this.title,
    required this.subtitle,
    this.attachments = 0,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final int attachments;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: ogBox(shadow: false),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OG.body(size: 18, weight: FontWeight.w700),
                  ),
                  Text(subtitle, style: OG.muted()),
                ],
              ),
            ),
            if (attachments > 0) ...<Widget>[
              const SizedBox(width: 12),
              Row(
                key: const ValueKey<String>('entry-attachments'),
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.attach_file, size: 18, color: OG.mute),
                  Text('$attachments', style: OG.muted()),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
