import 'package:flutter/material.dart';

import 'choice_sheet.dart';

enum AttachChoice { library, camera, file }

/// The "+" sheet of the composer. Returns what the user picked, or null.
/// [includeCamera] false: no camera row (the composer has its own camera button).
Future<AttachChoice?> showAttachSheet(BuildContext context, {bool includeCamera = true}) async {
  final String? v = await showChoiceSheet(
    context,
    title: 'Add to message',
    choices: <SheetChoice>[
      const SheetChoice(value: 'library', label: 'Photo library'),
      if (includeCamera) const SheetChoice(value: 'camera', label: 'Camera'),
      const SheetChoice(value: 'file', label: 'File'),
    ],
  );
  for (final AttachChoice c in AttachChoice.values) {
    if (c.name == v) {
      return c;
    }
  }
  return null;
}
