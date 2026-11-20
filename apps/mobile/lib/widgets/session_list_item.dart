import 'package:flutter/material.dart';

import '../theme.dart';

/// Row for a past session. Line 1: bold title and the tag. Line 2: muted
/// subtitle on the left, muted trailing text on the right.
class SessionListItem extends StatelessWidget {
  const SessionListItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.tag,
    this.onTap,
  });

  /// Opens the session. Null: the row is not tappable.
  final VoidCallback? onTap;

  /// The focus of the session ("Upper", "Easy"), shown as a small tag.
  final String? tag;

  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final bool hasTag = tag != null && tag!.isNotEmpty;
    final Widget row = Container(
      decoration: ogBox(shadow: false),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The title keeps its width (up to 60% of the row); a long tag is cut.
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) => Row(
              children: <Widget>[
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * (hasTag ? 0.6 : 1)),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OG.body(size: 18, weight: FontWeight.w700),
                  ),
                ),
                if (hasTag) ...<Widget>[
                  if (title.isNotEmpty) const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: OG.ink, width: 1.5),
                      ),
                      child: Text(
                        tag!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OG.muted(size: 13, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: OG.muted()),
              ),
              const SizedBox(width: 12),
              Text(trailing, style: OG.muted()),
            ],
          ),
        ],
      ),
    );
    return onTap == null
        ? row
        : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row);
  }
}
