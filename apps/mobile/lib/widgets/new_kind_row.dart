import 'package:flutter/material.dart';

import '../theme.dart';
import 'dashed_box.dart';

/// The dashed row that opens a form: a label and a chevron, no text field.
class NewKindRow extends StatelessWidget {
  const NewKindRow({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DashedBox(
        color: OG.card,
        radius: 20,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(label, style: OG.body().copyWith(fontWeight: FontWeight.w700))),
              const Icon(Icons.chevron_right, size: 28, color: OG.ink),
            ],
          ),
        ),
      ),
    );
  }
}
