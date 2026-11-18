import 'package:flutter/material.dart';

import '../theme.dart';

/// A square picture tile: a photo, or a quiet frame while it loads or when it
/// cannot show. With [onRemove] a small x badge sits on the corner.
class AttachmentThumb extends StatelessWidget {
  const AttachmentThumb({super.key, this.image, this.size = 56, this.onRemove});

  /// Null shows the empty frame (still loading).
  final ImageProvider? image;
  final double size;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final ImageProvider? img = image;
    final Widget tile = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: OG.soft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OG.ink, width: OG.borderWidth),
      ),
      child: img == null
          ? const SizedBox.shrink()
          : Image(
              image: img,
              fit: BoxFit.cover,
              errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                  const Icon(Icons.image_not_supported_outlined, size: 22, color: OG.mute),
            ),
    );
    final VoidCallback? remove = onRemove;
    if (remove == null) {
      return tile;
    }
    // The badge is 22 px to look, 44 px to tap; it sits over the top right corner.
    return SizedBox(
      width: size + 10,
      height: size + 10,
      child: Stack(
        children: <Widget>[
          Positioned(left: 0, bottom: 0, child: tile),
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              key: const ValueKey<String>('thumb-remove'),
              behavior: HitTestBehavior.opaque,
              onTap: remove,
              child: const SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: OG.ink, shape: BoxShape.circle),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: Icon(Icons.close, size: 14, color: OG.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
