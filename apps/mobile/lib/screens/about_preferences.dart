import 'package:flutter/material.dart';

import '../models.dart';
import '../stores/context_store.dart';
import '../theme.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/note_box.dart';
import '../widgets/section_header.dart';

/// The coach notes, shown as Preferences: add, switch off or on, remove.
class AboutPreferences extends StatelessWidget {
  const AboutPreferences({super.key, required this.notes, this.onAdd, this.onChange});

  final ContextStore notes;

  /// Opens the chat for a new note (ADR-032, step D). Null: no add action.
  final VoidCallback? onAdd;

  /// Opens the chat to change one note. Null: a row is not tappable.
  final void Function(ContextItem)? onChange;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notes,
      builder: (BuildContext context, Widget? child) {
        final List<ContextItem> items = notes.items;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SectionHeader(title: 'Preferences', action: onAdd == null ? null : '+ Add', onAction: onAdd),
            if (notes.error != null)
              NoteBox(title: 'Preferences are not available.', message: notes.error!)
            else if (items.isEmpty)
              const NoteBox(
                title: 'No preferences yet.',
                message: 'Add what the coach should know: warm-up, gym, logging.',
              )
            else
              Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                decoration: ogBox(),
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < items.length; i++) ...<Widget>[
                      if (i > 0) const Divider(height: 1, thickness: 1.5, color: OG.soft),
                      _row(context, items[i]),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _remove(BuildContext context, ContextItem c) async {
    final bool ok = await confirmDelete(context, title: 'Delete this note?', label: 'Delete note');
    if (ok && context.mounted) {
      await notes.remove(c);
    }
  }

  Widget _row(BuildContext context, ContextItem c) {
    final Color color = c.active ? OG.ink : OG.mute;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              key: ValueKey<String>('pref-change-${c.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: onChange == null ? null : () => onChange!(c),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  c.topic.toUpperCase(),
                  style: OG.muted(size: 12, weight: FontWeight.w700).copyWith(letterSpacing: 0.5),
                ),
                Text(
                  c.text,
                  style: OG.body(size: 15, color: color).copyWith(
                    decoration: c.active ? null : TextDecoration.lineThrough,
                  ),
                ),
              ],
              ),
            ),
          ),
          Switch(
            key: ValueKey<String>('pref-switch-${c.id}'),
            value: c.active,
            activeTrackColor: OG.accent,
            onChanged: (bool v) => notes.setActive(c, v),
          ),
          IconButton(
            key: ValueKey<String>('pref-remove-${c.id}'),
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => _remove(context, c),
          ),
        ],
      ),
    );
  }
}
