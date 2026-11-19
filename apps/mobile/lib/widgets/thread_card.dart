import 'package:flutter/material.dart';

import '../theme.dart';

/// A chat thread in the list: title and its last message.
class ThreadCard extends StatelessWidget {
  const ThreadCard({
    super.key,
    required this.title,
    required this.onTap,
    this.lastMessage,
    this.onDelete,
    this.onRename,
    this.label,
  });

  final String title;
  final String? lastMessage;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;

  /// A small tag next to the title, for example "Program".
  final String? label;

  @override
  Widget build(BuildContext context) {
    final String? last = lastMessage;
    final VoidCallback? del = onDelete;
    final VoidCallback? ren = onRename;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        constraints: const BoxConstraints(minHeight: 76),
        decoration: ogBox(),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(child: Text(title, style: OG.body(size: 19, weight: FontWeight.w700))),
                      if (label != null) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          key: const ValueKey<String>('thread-label'),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: ogBox(color: OG.done, radius: 8, shadow: false),
                          child: Text(label!, style: OG.muted(size: 12)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    (last == null || last.isEmpty) ? 'No messages yet' : last,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: OG.muted(size: 15),
                  ),
                ],
              ),
            ),
            if (ren != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: ren,
                child: const SizedBox(
                  key: ValueKey<String>('thread-rename'),
                  width: 48,
                  height: 48,
                  child: Icon(Icons.edit_outlined, size: 24),
                ),
              ),
            if (del != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: del,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.delete_outline, size: 24),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
