import 'package:flutter/material.dart';

import '../theme.dart';

/// The action on an exercise card that opens the chat about this exercise.
class AskCoachLine extends StatelessWidget {
  const AskCoachLine({super.key, required this.onTap, this.label = 'Change this exercise'});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        key: const ValueKey<String>('ask-coach'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: <Widget>[
              const Icon(Icons.auto_awesome_outlined, size: 18, color: OG.ink),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: OG.body(size: 15, weight: FontWeight.w700))),
              const Icon(Icons.chevron_right, size: 20, color: OG.mute),
            ],
          ),
        ),
      ),
    );
  }
}
