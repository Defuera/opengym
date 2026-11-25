import 'package:flutter/material.dart';

import '../theme.dart';

/// A title and a quiet line on the left, a switch on the right.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.switchKey,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Key? switchKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        decoration: ogBox(shadow: false),
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: OG.body(size: 17, weight: FontWeight.w700)),
                  Text(subtitle, style: OG.muted(size: 14)),
                ],
              ),
            ),
            Switch(key: switchKey, value: value, activeTrackColor: OG.accent, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
