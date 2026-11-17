import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';

/// A choice row in a sheet: bold title, one muted line, a chevron. The first
/// ("most likely") row is [primary] (blue).
class ProposalRow extends StatelessWidget {
  const ProposalRow({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle = '',
    this.primary = false,
    this.onAsk,
    this.askLabel = 'Ask for a custom session',
  });

  final String title;
  final String subtitle;
  final bool primary;
  final VoidCallback? onTap;

  /// A small secondary action before the chevron (a pencil). Null hides it.
  final VoidCallback? onAsk;
  final String askLabel;

  @override
  Widget build(BuildContext context) {
    final Color fg = primary ? OG.white : OG.ink;
    return OgButton(
      variant: primary ? OgVariant.accent : OgVariant.plain,
      minHeight: 80,
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      onPressed: onTap,
      child: SizedBox(
        width: double.infinity,
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
                    style: OG.display(24, color: fg),
                  ),
                  if (subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: OG.body(
                        size: 16,
                        color: primary ? OG.white : OG.mute,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onAsk != null)
              Tooltip(
                message: askLabel,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onAsk,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.edit_outlined, size: 22, color: fg),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 28, color: fg),
          ],
        ),
      ),
    );
  }
}
