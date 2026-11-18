import 'package:flutter/material.dart';

import 'choice_sheet.dart';

enum AttachChoice { library, camera, file }

/// The "+" sheet of the composer. Returns what the user picked, or null.
Future<AttachChoice?> showAttachSheet(BuildContext context) async {
  final String? v = await showChoiceSheet(
    context,
    title: 'Add to message',
    choices: const <SheetChoice>[
      SheetChoice(value: 'library', label: 'Photo library'),
      SheetChoice(value: 'camera', label: 'Camera'),
      SheetChoice(value: 'file', label: 'File'),
    ],
  );
  for (final AttachChoice c in AttachChoice.values) {
    if (c.name == v) {
      return c;
    }
  }
  return null;
}
