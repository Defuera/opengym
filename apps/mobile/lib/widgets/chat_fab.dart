import 'package:flutter/material.dart';

import '../theme.dart';

/// The one floating chat button of the session screen.
class ChatFab extends StatelessWidget {
  const ChatFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Chat with the coach',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: OG.accent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: OG.ink, width: OG.borderWidth),
            boxShadow: const <BoxShadow>[BoxShadow(color: OG.ink, offset: Offset(0, 4))],
          ),
          child: const Icon(Icons.chat_bubble_outline, size: 26, color: OG.white),
        ),
      ),
    );
  }
}
