import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';
import 'og_sheet.dart';

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

/// Bottom sheet with a title, an optional [message] and a stack of buttons. Returns the tapped value.
Future<String?> showChoiceSheet(
  BuildContext context, {
  required String title,
  required List<SheetChoice> choices,
  String? message,
}) {
  return showOgSheet<String>(
    context,
    (BuildContext ctx) {
      final List<Widget> items = <Widget>[];
      if (message != null) {
        items.add(Text(message, style: OG.muted()));
        items.add(const SizedBox(height: 16));
      }
      for (final SheetChoice c in choices) {
        items.add(OgButton(
          variant: c.variant,
          onPressed: () => Navigator.of(ctx).pop(c.value),
          child: Text(c.label),
        ));
        items.add(const SizedBox(height: 8));
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      );
    },
    title: title,
  );
}
