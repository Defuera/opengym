import 'package:flutter/material.dart';

import '../theme.dart';
import 'text_sheet.dart';

/// The person's comment on an exercise in this session: "Add comment" when
/// there is none, else the text. A tap opens a sheet to write or change it; an
/// empty text removes it.
class CommentLine extends StatelessWidget {
  const CommentLine({super.key, required this.comment, required this.onChanged, this.maxLength = 1000});

  final String? comment;

  /// Gets the new text (trimmed); empty means "no comment".
  final ValueChanged<String> onChanged;
  final int maxLength;

  Future<void> _edit(BuildContext context) async {
    final String? text = await showTextSheet(
      context,
      title: 'Comment',
      label: 'How did it go?',
      hint: 'For example: I feel my shoulder a bit',
      actionLabel: 'Save',
      initialText: comment,
      allowEmpty: true,
      maxLines: 5,
      maxLength: maxLength,
    );
    if (text != null) {
      onChanged(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? c = comment;
    return Semantics(
      button: true,
      child: GestureDetector(
        key: const ValueKey<String>('exercise-comment'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _edit(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
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
                  c ?? 'Add comment',
                  style: c == null ? OG.muted(size: 14, weight: FontWeight.w600) : OG.body(size: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
