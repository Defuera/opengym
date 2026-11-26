import 'package:flutter/material.dart';

import '../data/pickers.dart';
import '../widgets/attach_sheet.dart';
import '../widgets/attachment_strip.dart';
import 'chat_file_thumb.dart';

/// The "+" of every composer: asks what to add (library, file, and the camera
/// when [includeCamera]), runs the device picker and hands each pick to [add].
/// The library picks several photos at once. A composer that has its own camera
/// button passes `includeCamera: false`. Returns a short message when the picker
/// failed, null otherwise (also when the person cancelled).
Future<String?> runAttachFlow(
  BuildContext context,
  Pickers pickers,
  void Function(UploadItem) add, {
  bool includeCamera = true,
}) async {
  final AttachChoice? choice = await showAttachSheet(context, includeCamera: includeCamera);
  if (choice == null) {
    return null;
  }
  try {
    if (choice == AttachChoice.file) {
      for (final UploadItem f in await pickers.pickFiles()) {
        add(f);
      }
    } else if (choice == AttachChoice.library) {
      for (final UploadItem p in await pickers.pickPhotos()) {
        add(p);
      }
    } else {
      final UploadItem? p = await pickers.pickPhoto(camera: true);
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

/// The camera button of the composer: opens the camera at once and hands the
/// photo to [add]. Returns a short message when the camera failed, else null.
Future<String?> runCameraFlow(Pickers pickers, void Function(UploadItem) add) async {
  try {
    final UploadItem? p = await pickers.pickPhoto(camera: true);
    if (p != null) {
      add(p);
    }
    return null;
  } catch (_) {
    return 'Could not open the camera or library.';
  }
}
