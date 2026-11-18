import 'package:flutter/material.dart';

import 'attachment_chip.dart';
import 'attachment_thumb.dart';

/// One thing waiting to be sent. [image] set means it shows as a picture.
class StripItem {
  const StripItem({required this.name, this.image});

  final String name;
  final ImageProvider? image;
}

/// The row above the text field: pictures as thumbnails, other files as chips.
/// Scrolls sideways when there are many.
class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({super.key, required this.items, required this.onRemove});

  final List<StripItem> items;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (BuildContext c, int i) => const SizedBox(width: 6),
        itemBuilder: (BuildContext c, int i) {
          final StripItem it = items[i];
          if (it.image != null) {
            return AttachmentThumb(image: it.image, onRemove: () => onRemove(i));
          }
          return Align(
            alignment: Alignment.bottomCenter,
            child: AttachmentChip(name: it.name, onRemove: () => onRemove(i)),
          );
        },
      ),
    );
  }
}
