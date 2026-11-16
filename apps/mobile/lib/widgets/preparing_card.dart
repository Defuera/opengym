import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';

/// "Preparing your session..." with a spinner and an immediate way out.
class PreparingCard extends StatelessWidget {
  const PreparingCard({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: ogBox(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 3, color: OG.ink),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(title, style: OG.display(26))),
            ],
          ),
          const SizedBox(height: 10),
          Text(message, style: OG.muted()),
          const SizedBox(height: 18),
          OgButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
