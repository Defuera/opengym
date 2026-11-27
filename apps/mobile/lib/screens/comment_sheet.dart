import 'dart:async';

import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../data/convex_types.dart';
import '../data/upload_item.dart';
import '../models.dart';
import '../planner.dart';
import '../store.dart';
import '../stores/voice_controller.dart';
import '../theme.dart';
import '../widgets/attachment_strip.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/composer_bar.dart';
import '../widgets/og_sheet.dart';
import 'attach_flow.dart';
import 'chat_file_thumb.dart';

const String commentOfflineNote = 'Offline. The text is saved now. Photos need a connection.';
const String commentUploadFailed = 'Could not upload the photos. Try again, or remove them.';

/// What the comment sheet gives back: the new text (trimmed, may be empty),
/// the ids of the photos that stay (saved ones first, then the new ones, which
/// are uploaded already) and the ids of saved photos the person took away.
class CommentEdit {
  const CommentEdit({required this.text, required this.fileIds, required this.removedIds});

  final String text;
  final List<String> fileIds;
  final List<String> removedIds;
}

/// The sheet of the comment on an exercise (ADR-043). It is the same
/// composer as the chat ([ComposerBar]): text, camera, library, the "+" menu
/// and voice, whose text goes into the field. Returns null when the person
/// closes it, else a [CommentEdit].
Future<CommentEdit?> showCommentSheet(
  BuildContext context,
  AppDeps deps, {
  required String? text,
  required List<String> fileIds,
}) {
  return showOgSheet<CommentEdit>(
    context,
    (BuildContext c) => CommentSheetBody(deps: deps, text: text, fileIds: fileIds),
    title: 'Comment',
    scroll: false,
  );
}

class CommentSheetBody extends StatefulWidget {
  const CommentSheetBody({super.key, required this.deps, required this.text, required this.fileIds});

  final AppDeps deps;
  final String? text;
  final List<String> fileIds;

  @override
  State<CommentSheetBody> createState() => _CommentSheetBodyState();
}

class _CommentSheetBodyState extends State<CommentSheetBody> {
  late final TextEditingController _text = TextEditingController(text: widget.text);
  final FocusNode _focus = FocusNode();
  late final VoiceController _voice;
  late final List<String> _saved = List<String>.of(widget.fileIds);
  final List<UploadItem> _added = <UploadItem>[];
  final Map<UploadItem, String> _uploaded = Map<UploadItem, String>.identity();
  final Map<String, ImageProvider> _remote = <String, ImageProvider>{};
  final List<String> _taken = <String>[];
  late final bool _hadComment = (widget.text ?? '').trim().isNotEmpty || widget.fileIds.isNotEmpty;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _voice = VoiceController(
      recorder: widget.deps.voice,
      transcribe: widget.deps.coach.transcribeVoice,
      onText: _putVoiceText,
      onDiscard: widget.deps.coach.discardVoice,
    );
    for (final String id in _saved) {
      if (widget.deps.coach.localFile(id) == null) {
        _lookUp(id);
      }
    }
  }

  /// A saved photo this phone does not hold shows from its address on the server.
  Future<void> _lookUp(String id) async {
    final FileLink? l = await widget.deps.coach.fileLink(id);
    final String? url = l?.url;
    if (mounted && l != null && url != null && l.meta.kind == 'image') {
      setState(() => _remote[id] = NetworkImage(url));
    }
  }

  /// The text of a recording goes into the field (after a space when the field holds text); the person checks it and saves.
  void _putVoiceText(String heard) {
    final String have = _text.text.trimRight();
    final String joined = have.isEmpty ? heard : '$have $heard';
    _text.value = TextEditingValue(text: joined, selection: TextSelection.collapsed(offset: joined.length));
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _voice.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  int get _count => _saved.length + _added.length;

  void _addPicked(UploadItem item) {
    if (!item.mime.startsWith('image/')) {
      _error = 'A comment holds photos only.';
      return;
    }
    if (_count >= maxCommentFiles) {
      _error = 'A comment holds up to $maxCommentFiles photos.';
      return;
    }
    _added.add(item);
  }

  Future<void> _attach() async {
    _error = null;
    final String? e = await runAttachFlow(context, widget.deps.pickers, _addPicked, includeCamera: false);
    if (mounted) {
      setState(() => _error = e ?? _error);
    }
  }

  Future<void> _camera() async {
    _error = null;
    final String? e = await runCameraFlow(widget.deps.pickers, _addPicked);
    if (mounted) {
      setState(() => _error = e ?? _error);
    }
  }

  List<StripItem> _strip() => <StripItem>[
        for (final String id in _saved) StripItem(name: 'Photo', image: _savedImage(id)),
        for (final UploadItem u in _added) StripItem(name: u.name, image: imageForUpload(u)),
      ];

  ImageProvider? _savedImage(String id) {
    final UploadItem? local = widget.deps.coach.localFile(id);
    return local != null ? imageForUpload(local) : _remote[id];
  }

  /// A photo of an unsent draft goes without a question; a saved photo asks first (the delete rule).
  Future<void> _remove(int i) async {
    if (i < _saved.length) {
      final bool ok = await confirmDelete(context, title: 'Remove this photo?', label: 'Remove photo');
      if (ok && mounted) {
        setState(() => _taken.add(_saved.removeAt(i)));
      }
      return;
    }
    setState(() => _added.removeAt(i - _saved.length));
  }

  Future<void> _save() async {
    if (_busy) {
      return;
    }
    final String text = _text.text.trim();
    if (text.isEmpty && _count == 0) {
      // Nothing is left: the saved comment goes, after a question.
      if (_hadComment) {
        final bool ok = await confirmDelete(context, title: 'Remove this comment?', label: 'Remove comment');
        if (!ok || !mounted) {
          return;
        }
      }
      _done(text, const <String>[]);
      return;
    }
    // The text never waits for the network. Only new photos do: they upload first.
    final List<String> ids = List<String>.of(_saved);
    if (_added.isNotEmpty) {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        for (final UploadItem u in _added) {
          final String id = _uploaded.putIfAbsent(u, newId);
          await widget.deps.client.uploadFile(fileId: id, name: u.name, mime: u.mime, bytes: await u.read());
          widget.deps.coach.rememberFile(id, u);
          ids.add(id);
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = commentUploadFailed;
          });
        }
        return;
      }
    }
    _done(text, ids);
  }

  void _done(String text, List<String> ids) {
    FocusManager.instance.primaryFocus?.unfocus(); // the keyboard closes with the sheet
    Navigator.of(context).pop(CommentEdit(text: text, fileIds: ids, removedIds: List<String>.of(_taken)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_voice, widget.deps.connection]),
      builder: (BuildContext context, Widget? child) {
        final bool online = widget.deps.connection.connected;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('How did it go?', key: const ValueKey<String>('comment-question'), style: OG.muted(size: 15, weight: FontWeight.w600)),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, key: const ValueKey<String>('comment-error'), style: OG.body(size: 15, weight: FontWeight.w600)),
              ),
            ComposerBar(
              hint: 'For example: I feel my shoulder a bit',
              controller: _text,
              focusNode: _focus,
              maxLength: maxExerciseComment,
              // The text, the mic and Save never switch off for the link; only new photos need it (ADR-043).
              quietNote: online ? null : commentOfflineNote,
              attachOff: !online,
              attachments: _strip(),
              onRemoveAttachment: _busy ? null : _remove,
              onAttach: _attach,
              onCamera: _camera,
              onSend: _save,
              sending: _busy,
              sendLabel: 'Save',
              sendWhenEmpty: _hadComment,
              onMic: _voice.transcribing ? null : _voice.start,
              recording: _voice.recording,
              recordSeconds: _voice.seconds,
              recordLevels: _voice.levels,
              onCancelRecording: _voice.cancel,
              onStopRecording: _voice.stopAndTranscribe,
              transcribing: _voice.transcribing,
              voiceNote: _voice.note,
              onRetryVoice: _voice.canRetry ? _voice.retry : null,
              onDiscardVoice: (_voice.canRetry || _voice.transcribing) ? _voice.cancel : null,
            ),
          ],
        );
      },
    );
  }
}

/// Opens the comment sheet for the open exercise and saves what comes back.
/// The text and the photo ids go into the open session in one write (the
/// outbox path of ADR-003); a saved photo the person took away is removed
/// from the server afterwards, and a failure there leaves only an unused file.
Future<void> editExerciseComment(BuildContext context, AppDeps deps, AppStore store, Exercise ex) async {
  final CommentEdit? r = await showCommentSheet(context, deps, text: ex.comment, fileIds: ex.commentFileIds);
  if (r == null) {
    return;
  }
  store.setComment(r.text, r.fileIds);
  for (final String id in r.removedIds) {
    unawaited(deps.client.removeFile(id).catchError((Object _) {}));
  }
}
