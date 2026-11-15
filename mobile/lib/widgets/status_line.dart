import 'package:flutter/material.dart';

import '../theme.dart';

/// Small dot plus muted text, e.g. "Offline: saved on this phone".
class StatusLine extends StatelessWidget {
  const StatusLine({super.key, required this.text, required this.connected});

  final String text;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: connected ? OG.accent : OG.card,
            shape: BoxShape.circle,
            border: Border.all(color: OG.ink, width: 2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: OG.muted(size: 13))),
      ],
    );
  }
}
