import 'package:flutter/material.dart';

import '../theme.dart';
import 'choice_sheet.dart';
import 'set_editor_card.dart';
import 'set_row.dart';

/// Plain data for one set, so widgets need no model imports.
class SetRowData {
  const SetRowData({
    required this.id,
    required this.reps,
    required this.kg,
    this.done = false,
    this.failed = false,
    this.isMax = false,
  });

  /// Stable identity, used as the swipe key.
  final Object id;
  final int reps;
  final String kg;
  final bool done;
  final bool failed;
  final bool isMax;
}

/// Vertical list of sets. Only the [selected] one is expanded into an editor.
/// Swipe a row left to remove it (not allowed for the last remaining set).
/// Scrolls the editor into view when the selection changes.
class SetList extends StatefulWidget {
  const SetList({
    super.key,
    required this.sets,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    required this.onRemove,
    required this.onRepsChanged,
    required this.onKgChanged,
    required this.onFailedChanged,
    this.onToggle,
    this.checkPrefix = 'set-check',
  });

  final List<SetRowData> sets;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<double> onKgChanged;
  final ValueChanged<bool> onFailedChanged;

  /// Tap on a set's check control (complete or undo). Null: no check controls.
  final ValueChanged<int>? onToggle;

  /// Check keys are `'<checkPrefix>-<index>'`.
  final String checkPrefix;

  @override
  State<SetList> createState() => _SetListState();
}

class _SetListState extends State<SetList> {
  final GlobalKey _editorKey = GlobalKey();

  @override
  void didUpdateWidget(covariant SetList old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected || old.sets.length != widget.sets.length) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        final BuildContext? c = _editorKey.currentContext;
        if (mounted && c != null) {
          Scrollable.ensureVisible(
            c,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[];
    for (int i = 0; i < widget.sets.length; i++) {
      final SetRowData x = widget.sets[i];
      if (i == widget.selected) {
        items.add(Padding(
          key: _editorKey,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SetEditorCard(
            number: i + 1,
            title: x.isMax ? 'Max attempt' : 'Set ${i + 1}',
            reps: '${x.reps}',
            kg: x.kg,
            failed: x.failed,
            done: x.done,
            onCheck: widget.onToggle == null ? null : () => widget.onToggle!(i),
            checkKey: ValueKey<String>('${widget.checkPrefix}-$i'),
            onRepsChanged: widget.onRepsChanged,
            onKgChanged: widget.onKgChanged,
            onFailedChanged: widget.onFailedChanged,
          ),
        ));
        continue;
      }
      final Widget row = SetRow(
        number: i + 1,
        reps: x.reps,
        kg: x.kg,
        done: x.done,
        failed: x.failed,
        isMax: x.isMax,
        onTap: () => widget.onSelect(i),
        onCheck: widget.onToggle == null ? null : () => widget.onToggle!(i),
        checkKey: ValueKey<String>('${widget.checkPrefix}-$i'),
      );
      items.add(Dismissible(
        key: ObjectKey(x.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (DismissDirection d) async {
          if (widget.sets.length <= 1) {
            return false;
          }
          return confirmDelete(context, title: 'Delete this set?', label: 'Delete set');
        },
        onDismissed: (DismissDirection d) => widget.onRemove(i),
        background: Container(
          color: OG.soft,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          child: Text('Remove', style: OG.body(size: 14, weight: FontWeight.w700, color: OG.mute)),
        ),
        child: row,
      ));
    }
    items.add(AddSetRow(onTap: widget.onAdd));
    return Column(children: items);
  }
}
