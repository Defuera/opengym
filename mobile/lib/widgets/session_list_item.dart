import 'package:flutter/material.dart';

import '../theme.dart';

/// Row for a past session: bold title, muted subtitle, muted trailing text.
class SessionListItem extends StatelessWidget {
  const SessionListItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

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
                Text(title, style: OG.body(size: 18, weight: FontWeight.w700)),
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
