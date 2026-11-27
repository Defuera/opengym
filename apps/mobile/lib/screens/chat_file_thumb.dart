import 'dart:io';

import 'package:flutter/material.dart';

import '../data/convex_types.dart';
import '../data/upload_item.dart';
import '../stores/coach_store.dart';
import '../widgets/attachment_chip.dart';
import '../widgets/attachment_thumb.dart';

/// The picture for an upload that is an image, else null. Used for the
/// composer strip and for a message sent from this device.
ImageProvider? imageForUpload(UploadItem u) {
  if (!u.mime.startsWith('image/')) {
    return null;
  }
  final List<int>? b = u.bytes;
  return b != null ? MemoryImage(b as dynamic) : FileImage(File(u.path));
}

/// One sent file inside a message bubble: a thumbnail for a photo, a chip for
/// anything else. A message from this device shows the local photo at once;
/// older ones use the file address from the server.
class ChatFileThumb extends StatefulWidget {
  const ChatFileThumb({super.key, required this.coach, required this.fileId, this.size = 72});

  final CoachStore coach;
  final String fileId;
  final double size;

  @override
  State<ChatFileThumb> createState() => _ChatFileThumbState();
}

class _ChatFileThumbState extends State<ChatFileThumb> {
  UploadItem? _local;
  Future<FileLink?>? _link;

  @override
  void initState() {
    super.initState();
    _local = widget.coach.localFile(widget.fileId);
    if (_local == null) {
      _link = widget.coach.fileLink(widget.fileId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final UploadItem? local = _local;
    if (local != null) {
      final ImageProvider? img = imageForUpload(local);
      return img != null ? AttachmentThumb(image: img, size: widget.size) : AttachmentChip(name: local.name);
    }
    return FutureBuilder<FileLink?>(
      future: _link,
      builder: (BuildContext c, AsyncSnapshot<FileLink?> snap) {
        final FileLink? l = snap.data;
        if (snap.connectionState != ConnectionState.done) {
          return AttachmentThumb(size: widget.size);
        }
        if (l == null) {
          return const AttachmentChip(name: 'File');
        }
        final String? url = l.url;
        if (l.meta.kind == 'image' && url != null) {
          return AttachmentThumb(image: NetworkImage(url), size: widget.size);
        }
        return AttachmentChip(name: l.meta.name);
      },
    );
  }
}
