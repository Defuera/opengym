import 'package:flutter/material.dart';

import '../theme.dart';

/// Row for a past session: bold title, muted subtitle, muted trailing text.
class SessionListItem extends StatelessWidget {
  const SessionListItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.tag,
  });

  /// The focus of the session ("Upper", "Easy"), shown as a small tag.
  final String? tag;

  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: ogBox(shadow: false),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: OG.body(size: 18, weight: FontWeight.w700),
                      ),
                    ),
                    if (tag != null && tag!.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: OG.ink, width: 1.5),
                        ),
                        child: Text(tag!, style: OG.muted(size: 13, weight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
                Text(subtitle, style: OG.muted()),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(trailing, style: OG.muted()),
        ],
      ),
    );
  }
}
