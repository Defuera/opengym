import 'package:flutter/material.dart';

import '../theme.dart';

/// File name pill with a remove button.
class AttachmentChip extends StatelessWidget {
  const AttachmentChip({super.key, required this.name, this.onRemove});

  final String name;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        color: OG.soft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: OG.ink, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.attach_file, size: 18),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OG.body(size: 15, weight: FontWeight.w600),
            ),
          ),
          if (onRemove != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.close, size: 18),
              ),
            )
          else
            const SizedBox(width: 14),
        ],
      ),
    );
  }
}
