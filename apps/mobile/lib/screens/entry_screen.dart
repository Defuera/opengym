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
import '../widgets/sheet_link.dart';
import 'entry_form_screen.dart';
import 'goals_screen.dart';
import 'session_recap_screen.dart';

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
    final bool sure = await confirmDelete(
      context,
      title: 'Delete this note?',
      label: 'Delete note',
      message: 'It is removed from your log now and erased for good after 72 hours, with its files.',
    );
    if (!sure) {
      return;
    }
    final bool ok = await deps.entries.remove(entryId);
    if (ok && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Edit and Delete live behind the menu button at the top right.
  Future<void> _menu(BuildContext context, LogEntry e) async {
    final String? c = await showChoiceSheet(
      context,
      title: 'Note',
      choices: const <SheetChoice>[
        SheetChoice(value: 'edit', label: 'Edit', key: ValueKey<String>('entry-edit')),
        SheetChoice(value: 'delete', label: 'Delete', variant: OgVariant.dashed, key: ValueKey<String>('entry-delete')),
      ],
    );
    if (!context.mounted) {
      return;
    }
    if (c == 'edit') {
      _edit(context, e);
    } else if (c == 'delete' && !deps.entries.busy) {
      _delete(context);
    }
  }

  /// What the log chat made with this entry, with a link where a screen exists
  /// (a session has its recap, a goal the goals list).
  List<Widget> _made(BuildContext context, LogEntry e) {
    final EntryMade? m = e.read?.made;
    if (m == null) {
      return const <Widget>[];
    }
    final bool session = m.sessionId != null && deps.store.sessionById(m.sessionId!) != null;
    final List<(String, VoidCallback?)> rows = <(String, VoidCallback?)>[
      if (m.sessionId != null)
        (
          'Session added',
          session
              ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (BuildContext c) => SessionRecapScreen(deps: deps, sessionId: m.sessionId!)))
              : null
        ),
      if (m.goalId != null)
        (
          'Goal added',
          () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (BuildContext c) => GoalsScreen(deps: deps)))
        ),
      if (m.limitId != null) ('Limit added', null),
      if (m.contextId != null) ('Note added', null),
    ];
    return <Widget>[
      Column(
        key: const ValueKey<String>('entry-made'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final (String, VoidCallback?) r in rows)
            r.$2 == null
                ? Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(r.$1, style: OG.body(size: 15, weight: FontWeight.w600)))
                : Padding(padding: const EdgeInsets.only(bottom: 8), child: SheetLink(label: r.$1, onTap: r.$2!)),
        ],
      ),
      const SizedBox(height: 8),
    ];
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
                    if (e != null)
                      OgIconButton(
                        key: const ValueKey<String>('entry-menu'),
                        icon: Icons.more_horiz,
                        onPressed: () => _menu(context, e),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                if (e == null)
                  const NoteBox(title: 'This note is gone.', message: 'It was deleted.')
                else ...<Widget>[
                  Text(entrySubtitle(e), key: const ValueKey<String>('entry-when'), style: OG.muted()),
                  const SizedBox(height: 12),
                  if (e.text.trim().isNotEmpty) ...<Widget>[
                    Text(e.text, key: const ValueKey<String>('entry-text'), style: OG.body()),
                    const SizedBox(height: 16),
                  ],
                  if (entrySeenLine(e) != null) ...<Widget>[
                    Text('The coach sees', style: OG.muted()),
                    Text(entrySeenLine(e)!, key: const ValueKey<String>('entry-seen'), style: OG.body(size: 15)),
                    const SizedBox(height: 16),
                  ],
                  for (final EntryFile f in e.files.where((EntryFile f) => f.isImage)) ...<Widget>[
                    EntryPhoto(url: f.url, name: f.name),
                    const SizedBox(height: 12),
                  ],
                  ..._made(context, e),
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
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
