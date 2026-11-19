import 'package:flutter/material.dart';

import '../theme.dart';

/// A row with a label and a switch, for "Show all chats".
class ShowAllRow extends StatelessWidget {
  const ShowAllRow({super.key, required this.value, required this.onChanged, this.label = 'Show all chats'});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: OG.muted(size: 15))),
        Switch(
          key: const ValueKey<String>('show-all-chats'),
          value: value,
          activeTrackColor: OG.accent,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
