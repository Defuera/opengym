import 'package:flutter/material.dart';

import '../theme.dart';

/// The person's comment on an exercise in this session: "Add comment" when
/// there is none, else the text, with small [photos] under it. A tap on the
/// line calls [onEdit] (the screen opens the composer sheet, ADR-043). The
/// photo widgets handle their own taps.
class CommentLine extends StatelessWidget {
  const CommentLine({super.key, required this.comment, required this.onEdit, this.photos = const <Widget>[]});

  final String? comment;

  /// The small photo tiles of the comment (built by the screen).
  final List<Widget> photos;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final String? c = comment;
    final bool empty = c == null && photos.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            button: true,
            child: GestureDetector(
              key: const ValueKey<String>('exercise-comment'),
              behavior: HitTestBehavior.opaque,
              onTap: onEdit,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.chat_bubble_outline, size: 18, color: OG.mute),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      empty ? 'Add comment' : (c ?? 'Photos'),
                      style: empty || c == null ? OG.muted(size: 14, weight: FontWeight.w600) : OG.body(size: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (photos.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Wrap(key: const ValueKey<String>('comment-photos'), spacing: 6, runSpacing: 6, children: photos),
            ),
          ],
        ],
      ),
    );
  }
}
