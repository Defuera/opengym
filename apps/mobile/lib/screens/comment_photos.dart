import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../data/convex_types.dart';
import '../data/upload_item.dart';
import '../widgets/attachment_chip.dart';
import '../widgets/entry_photo.dart';
import '../widgets/og_sheet.dart';
import 'chat_file_thumb.dart';

/// The small photo tiles of an exercise comment (ADR-043). A photo this phone
/// uploaded shows from the local file; any other is read from the server. A
/// tap opens the photo large in a sheet.
List<Widget> commentPhotoTiles(BuildContext context, AppDeps deps, List<String> fileIds, {double size = 56}) {
  return <Widget>[
    for (final String id in fileIds)
      GestureDetector(
        key: ValueKey<String>('comment-photo-$id'),
        behavior: HitTestBehavior.opaque,
        onTap: () => showCommentPhoto(context, deps, id),
        child: ChatFileThumb(coach: deps.coach, fileId: id, size: size),
      ),
  ];
}

/// Opens one comment photo large.
Future<void> showCommentPhoto(BuildContext context, AppDeps deps, String fileId) {
  return showOgSheet<void>(
    context,
    (BuildContext c) => _LargePhoto(deps: deps, fileId: fileId),
    title: 'Photo',
  );
}

class _LargePhoto extends StatelessWidget {
  const _LargePhoto({required this.deps, required this.fileId});

  final AppDeps deps;
  final String fileId;

  @override
  Widget build(BuildContext context) {
    final UploadItem? local = deps.coach.localFile(fileId);
    final ImageProvider? img = local == null ? null : imageForUpload(local);
    if (img != null) {
      return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image(image: img, fit: BoxFit.fitWidth));
    }
    return FutureBuilder<FileLink?>(
      future: deps.coach.fileLink(fileId),
      builder: (BuildContext c, AsyncSnapshot<FileLink?> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
        }
        final FileLink? l = snap.data;
        if (l == null) {
          return const AttachmentChip(name: 'The photo cannot be shown now.');
        }
        return EntryPhoto(url: l.url, name: l.meta.name);
      },
    );
  }
}
