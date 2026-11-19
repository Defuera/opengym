import 'package:flutter/material.dart';

import '../theme.dart';

/// One compact row for a program: a bold title, one muted line, and a chevron.
/// With [onOpen] a small button at the end opens the program itself, while a
/// tap on the row does the main thing (for example, starts the next session).
class ProgramRow extends StatelessWidget {
  const ProgramRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onOpen,
    this.openKey,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Opens the program. Null: the row shows a chevron only.
  final VoidCallback? onOpen;
  final Key? openKey;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        decoration: ogBox(radius: 16, offset: 3),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: OG.body(size: 17, weight: FontWeight.w800)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: OG.muted(size: 14)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (onOpen != null)
              GestureDetector(
                key: openKey,
                behavior: HitTestBehavior.opaque,
                onTap: onOpen,
                child: const SizedBox(width: 44, height: 44, child: Icon(Icons.more_horiz, size: 24, color: OG.ink)),
              )
            else
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.chevron_right, size: 26, color: OG.ink),
              ),
          ],
        ),
      ),
    );
  }
}
