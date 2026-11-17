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
  });

  final String title;
  final String? lastMessage;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;

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
                  Text(title, style: OG.body(size: 19, weight: FontWeight.w700)),
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
