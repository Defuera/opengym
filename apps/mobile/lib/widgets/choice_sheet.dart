import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';

class SheetChoice {
  const SheetChoice({
    required this.value,
    required this.label,
    this.variant = OgVariant.plain,
  });

  final String value;
  final String label;
  final OgVariant variant;
}

/// Bottom sheet with a title and a stack of buttons. Returns the tapped value.
Future<String?> showChoiceSheet(
  BuildContext context, {
  required String title,
  required List<SheetChoice> choices,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: OG.ground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: OG.ink, width: 2),
    ),
    builder: (BuildContext ctx) {
      final List<Widget> items = <Widget>[
        Text(title, style: OG.display(24)),
        const SizedBox(height: 14),
      ];
      for (final SheetChoice c in choices) {
        items.add(OgButton(
          variant: c.variant,
          onPressed: () => Navigator.of(ctx).pop(c.value),
          child: Text(c.label),
        ));
        items.add(const SizedBox(height: 8));
      }
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items,
          ),
        ),
      );
    },
  );
}
