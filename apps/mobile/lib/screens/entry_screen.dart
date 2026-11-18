import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../entry_text.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/attachment_chip.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/entry_photo.dart';
import '../widgets/note_box.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import 'entry_form_screen.dart';

/// One note: the full text, the photos, other files by name and the time.
/// It reads the store, so a change from the form shows at once.
class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key, required this.deps, required this.entryId});

  final AppDeps deps;
  final String entryId;

  Future<void> _edit(BuildContext context, LogEntry e) {
    return Navigator.of(context).push(
      MaterialPageRoute<bool>(builder: (BuildContext c) => EntryFormScreen(deps: deps, entry: e)),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final String? c = await showChoiceSheet(
      context,
      title: 'Delete this note?',
      message: 'It is removed from your log now and erased for good after 72 hours, with its files.',
      choices: const <SheetChoice>[
        SheetChoice(value: 'delete', label: 'Delete note'),
        SheetChoice(value: 'keep', label: 'Keep it', variant: OgVariant.dashed),
      ],
    );
    if (c != 'delete') {
      return;
    }
    final bool ok = await deps.entries.remove(entryId);
    if (ok && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: deps.entries,
      builder: (BuildContext context, Widget? child) {
        final LogEntry? e = deps.entries.byId(entryId);
        final String? err = deps.entries.error;
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    OgIconButton(
                      icon: Icons.chevron_left,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Note', style: OG.display(32))),
                  ],
                ),
                const SizedBox(height: 18),
                if (e == null)
                  const NoteBox(title: 'This note is gone.', message: 'It was deleted.')
                else ...<Widget>[
                  Text(entryWhen(e.at), key: const ValueKey<String>('entry-when'), style: OG.muted()),
                  const SizedBox(height: 12),
                  if (e.text.trim().isNotEmpty) ...<Widget>[
                    Text(e.text, key: const ValueKey<String>('entry-text'), style: OG.body()),
                    const SizedBox(height: 16),
                  ],
                  for (final EntryFile f in e.files.where((EntryFile f) => f.isImage)) ...<Widget>[
                    EntryPhoto(url: f.url, name: f.name),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final EntryFile f in e.files.where((EntryFile f) => !f.isImage))
                        AttachmentChip(name: f.name),
                    ],
                  ),
                  if (err != null) ...<Widget>[
                    const SizedBox(height: 12),
                    NoteBox(title: 'That did not work.', message: err),
                  ],
                  const SizedBox(height: 20),
                  OgButton(
                    key: const ValueKey<String>('entry-edit'),
                    onPressed: () => _edit(context, e),
                    child: const Text('Edit'),
                  ),
                  const SizedBox(height: 10),
                  OgButton(
                    key: const ValueKey<String>('entry-delete'),
                    variant: OgVariant.dashed,
                    onPressed: deps.entries.busy ? null : () => _delete(context),
                    child: const Text('Delete'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
