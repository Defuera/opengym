import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../data/upload_item.dart';
import '../entry_text.dart';
import '../models.dart';
import '../planner.dart';
import '../stores/entries_store.dart';
import '../theme.dart';
import '../widgets/attachment_chip.dart';
import '../widgets/attachment_thumb.dart';
import '../widgets/cta_button.dart';
import '../widgets/labeled_field.dart';
import '../widgets/note_box.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';

const String entryOfflineNote = 'Offline. Notes need a connection to save.';

/// The form that changes an existing [entry]: its photos and files (add or
/// remove), one text field, the time and Save. A new note is made in the log
/// chat, not here. A failed save keeps everything typed.
class EntryFormScreen extends StatefulWidget {
  const EntryFormScreen({super.key, required this.deps, required this.entry});

  final AppDeps deps;
  final LogEntry entry;

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  late final String _id;
  late DateTime _at;
  late final List<EntryFile> _existing;
  final List<NewEntryFile> _added = <NewEntryFile>[];
  String? _pickError;

  EntriesStore get _store => widget.deps.entries;

  @override
  void initState() {
    super.initState();
    final LogEntry e = widget.entry;
    _id = e.id;
    _text.text = e.text;
    _at = DateTime.fromMillisecondsSinceEpoch(e.at);
    _existing = List<EntryFile>.of(e.files);
    _store.error = null;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _store.error = null; // a failure of this form is not shown on the next screen
    super.dispose();
  }

  int get _fileCount => _existing.length + _added.length;

  bool get _canSave => _text.text.trim().isNotEmpty || _fileCount > 0;

  Future<void> _save() async {
    final bool ok = await _store.save(
      entryId: _id,
      text: _text.text,
      at: _at.millisecondsSinceEpoch,
      createdAt: widget.entry.createdAt,
      keep: <String>[for (final EntryFile f in _existing) f.id],
      added: _added,
    );
    if (ok && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _add(UploadItem item) {
    if (_fileCount >= entryMaxFiles) {
      setState(() => _pickError = 'A note holds up to $entryMaxFiles files.');
      return;
    }
    _added.add(NewEntryFile(item));
  }

  /// [src] is camera, gallery or file.
  Future<void> _pick(String src) async {
    final bool file = src == 'file';
    try {
      if (file) {
        for (final UploadItem f in await widget.deps.pickers.pickFiles()) {
          _add(f);
        }
      } else {
        final UploadItem? p = await widget.deps.pickers.pickPhoto(camera: src == 'camera');
        if (p != null) {
          _add(p);
        }
      }
      if (!mounted) {
        return;
      }
      setState(() => _pickError = _fileCount > entryMaxFiles ? _pickError : null);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _pickError =
          file ? 'Could not open the file picker.' : 'Could not open the camera or library.');
    }
  }

  ImageProvider _preview(UploadItem item) {
    final List<int>? b = item.bytes;
    return b != null ? MemoryImage(Uint8List.fromList(b)) : FileImage(File(item.path));
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _at.isAfter(now) ? now : _at,
      firstDate: DateTime(2000),
      lastDate: now.isAfter(_at) ? now : _at,
    );
    if (d != null) {
      setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? t =
        await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t != null) {
      setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_store, widget.deps.connection]),
      builder: (BuildContext context, Widget? child) {
        final bool online = widget.deps.connection.connected;
        final bool busy = _store.busy;
        final String err = _pickError ?? _store.error ?? '';
        final bool failed = _store.error != null;
        final int ms = _at.millisecondsSinceEpoch;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          OgIconButton(
                            icon: Icons.chevron_left,
                            onPressed: busy ? null : () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('Edit note', style: OG.display(32)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (_fileCount > 0) ...<Widget>[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.end,
                          children: <Widget>[
                            for (final EntryFile f in _existing)
                              f.isImage
                                  ? AttachmentThumb(
                                      image: f.url == null ? null : NetworkImage(f.url!),
                                      size: 96,
                                      onRemove: busy ? null : () => setState(() => _existing.remove(f)),
                                    )
                                  : AttachmentChip(
                                      name: f.name,
                                      onRemove: busy ? null : () => setState(() => _existing.remove(f)),
                                    ),
                            for (final NewEntryFile f in _added)
                              f.item.mime.startsWith('image/')
                                  ? AttachmentThumb(
                                      image: _preview(f.item),
                                      size: 96,
                                      onRemove: busy ? null : () => setState(() => _added.remove(f)),
                                    )
                                  : AttachmentChip(
                                      name: f.item.name,
                                      onRemove: busy ? null : () => setState(() => _added.remove(f)),
                                    ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                      LabeledField(
                        controller: _text,
                        focusNode: _focus,
                        hint: _fileCount > 0 ? 'Add a comment: "dinner"' : 'A meal, how you feel, anything.',
                        minLines: 3,
                        maxLines: 10,
                        maxLength: entryMaxText,
                        autocorrect: true,
                        keyboardType: TextInputType.multiline,
                        onChanged: (String v) => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          OgIconButton(
                            key: const ValueKey<String>('entry-camera'),
                            icon: Icons.photo_camera_outlined,
                            onPressed: busy ? null : () => _pick('camera'),
                          ),
                          const SizedBox(width: 8),
                          OgIconButton(
                            key: const ValueKey<String>('entry-library'),
                            icon: Icons.photo_library_outlined,
                            onPressed: busy ? null : () => _pick('gallery'),
                          ),
                          const SizedBox(width: 8),
                          OgIconButton(
                            key: const ValueKey<String>('entry-file'),
                            icon: Icons.attach_file,
                            onPressed: busy ? null : () => _pick('file'),
                          ),
                          const Spacer(),
                          _WhenLink(
                            key: const ValueKey<String>('entry-date'),
                            label: whenLabel(ms),
                            onTap: busy ? null : _pickDate,
                          ),
                          Text(', ', style: OG.muted()),
                          _WhenLink(
                            key: const ValueKey<String>('entry-time'),
                            label: clockText(ms),
                            onTap: busy ? null : _pickTime,
                          ),
                        ],
                      ),
                      if (!online) ...<Widget>[
                        const SizedBox(height: 14),
                        const NoteBox(title: 'Offline', message: entryOfflineNote),
                      ],
                      if (err.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 14),
                        NoteBox(
                          title: failed ? 'That did not work.' : 'Attach',
                          message: err,
                        ),
                      ],
                      if (busy) ...<Widget>[
                        const SizedBox(height: 14),
                        Row(
                          children: <Widget>[
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            ),
                            const SizedBox(width: 12),
                            Text(_store.progress ?? 'Saving…',
                                key: const ValueKey<String>('entry-progress'), style: OG.muted()),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: CtaButton(
                    label: failed ? 'Try again' : 'Save',
                    icon: Icons.check,
                    variant: OgVariant.accent,
                    onPressed: (_canSave && online && !busy) ? _save : null,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The day or the clock time of the note, as a quiet link that opens a picker.
class _WhenLink extends StatelessWidget {
  const _WhenLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          label,
          style: OG.muted(weight: FontWeight.w700).copyWith(decoration: TextDecoration.underline),
        ),
      ),
    );
  }
}
