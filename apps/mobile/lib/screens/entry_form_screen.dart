import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../data/upload_item.dart';
import '../entry_text.dart';
import '../models.dart';
import '../planner.dart';
import '../stores/entries_store.dart';
import '../theme.dart';
import '../widgets/attachment_chip.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/cta_button.dart';
import '../widgets/labeled_field.dart';
import '../widgets/note_box.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';

const String entryOfflineNote = 'Offline. Notes need a connection to save.';

/// The form of a note: new, or [entry] to change. One text field, Attach, the
/// time (now unless changed) and Save. A failed save keeps everything typed.
class EntryFormScreen extends StatefulWidget {
  const EntryFormScreen({super.key, required this.deps, this.entry});

  final AppDeps deps;
  final LogEntry? entry;

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final TextEditingController _text = TextEditingController();
  late final String _id;
  late DateTime _at;
  late final List<EntryFile> _existing;
  final List<NewEntryFile> _added = <NewEntryFile>[];
  String? _pickError;

  EntriesStore get _store => widget.deps.entries;

  @override
  void initState() {
    super.initState();
    final LogEntry? e = widget.entry;
    _id = e?.id ?? newId();
    _text.text = e?.text ?? '';
    _at = DateTime.fromMillisecondsSinceEpoch(e?.at ?? DateTime.now().millisecondsSinceEpoch);
    _existing = List<EntryFile>.of(e?.files ?? const <EntryFile>[]);
    _store.error = null;
  }

  @override
  void dispose() {
    _text.dispose();
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
      createdAt: widget.entry?.createdAt,
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

  Future<void> _attach() async {
    final String? src = await showChoiceSheet(
      context,
      title: 'Attach',
      choices: const <SheetChoice>[
        SheetChoice(value: 'camera', label: 'Take a photo'),
        SheetChoice(value: 'gallery', label: 'Choose from library'),
        SheetChoice(value: 'file', label: 'Choose a file'),
      ],
    );
    if (src == null) {
      return;
    }
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
                            child: Text(widget.entry == null ? 'New note' : 'Edit note',
                                style: OG.display(32)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      LabeledField(
                        label: 'Note',
                        controller: _text,
                        hint: 'A meal, a photo, anything.',
                        minLines: 4,
                        maxLines: 10,
                        maxLength: entryMaxText,
                        autocorrect: true,
                        keyboardType: TextInputType.multiline,
                        onChanged: (String v) => setState(() {}),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OgButton(
                              key: const ValueKey<String>('entry-date'),
                              onPressed: busy ? null : _pickDate,
                              child: Text(dateText(ms)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OgButton(
                              key: const ValueKey<String>('entry-time'),
                              onPressed: busy ? null : _pickTime,
                              child: Text(clockText(ms)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      OgButton(
                        key: const ValueKey<String>('entry-attach'),
                        onPressed: busy ? null : _attach,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.attach_file, size: 22),
                            SizedBox(width: 8),
                            Text('Attach'),
                          ],
                        ),
                      ),
                      if (_fileCount > 0) ...<Widget>[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: <Widget>[
                            for (final EntryFile f in _existing)
                              AttachmentChip(
                                name: f.name,
                                onRemove: busy ? null : () => setState(() => _existing.remove(f)),
                              ),
                            for (final NewEntryFile f in _added)
                              AttachmentChip(
                                name: f.item.name,
                                onRemove: busy ? null : () => setState(() => _added.remove(f)),
                              ),
                          ],
                        ),
                      ],
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
