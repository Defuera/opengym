import 'package:flutter/material.dart';

import '../data/pickers.dart';
import '../widgets/attach_sheet.dart';
import '../widgets/attachment_strip.dart';
import 'chat_file_thumb.dart';

/// The "+" of every composer: asks what to add (library, camera, file), runs
/// the device picker and hands each pick to [add]. Returns a short message
/// when the picker failed, null otherwise (also when the person cancelled).
Future<String?> runAttachFlow(
  BuildContext context,
  Pickers pickers,
  void Function(UploadItem) add,
) async {
  final AttachChoice? choice = await showAttachSheet(context);
  if (choice == null) {
    return null;
  }
  try {
    if (choice == AttachChoice.file) {
      for (final UploadItem f in await pickers.pickFiles()) {
        add(f);
      }
    } else {
      final UploadItem? p = await pickers.pickPhoto(camera: choice == AttachChoice.camera);
      if (p != null) {
        add(p);
      }
    }
    return null;
  } catch (_) {
    return choice == AttachChoice.file
        ? 'Could not open the file picker.'
        : 'Could not open the camera or library.';
  }
}

/// The composer strip for [items]: a thumbnail for a photo, a chip for a file.
List<StripItem> stripItems(List<UploadItem> items) => <StripItem>[
      for (final UploadItem u in items) StripItem(name: u.name, image: imageForUpload(u)),
    ];
