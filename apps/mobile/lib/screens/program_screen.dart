import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/sheet_link.dart';
import 'program_new_screen.dart';
import 'program_text.dart';

/// One program: its purpose, dates, phases (the current one marked), this
/// week's sessions with ticks, rules and tests. The actions are one tap away:
/// ask the coach for a change, and a menu with pause, resume, end and delete.
class ProgramScreen extends StatelessWidget {
  const ProgramScreen({super.key, required this.deps, required this.programId});

  final AppDeps deps;
  final String programId;

  Future<void> _change(BuildContext context, Program p) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext c) => ProgramNewScreen(deps: deps, change: p)),
    );
  }

  Future<void> _set(BuildContext context, String status) async {
    try {
      await deps.programs.setStatus(programId, status);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not change it. Try again.')));
      }
    }
  }

  Future<void> _delete(BuildContext context, Program p) async {
    final bool sure = await confirmDelete(
      context,
      title: 'Delete this program?',
      label: 'Delete program',
      message: 'It is removed now and erased for good later. The sessions you logged stay in your log.',
    );
    if (!sure || !context.mounted) {
      return;
    }
    final NavigatorState nav = Navigator.of(context);
    try {
      await deps.programs.remove(programId);
      nav.pop();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete it. Try again.')));
      }
    }
  }

  Future<void> _menu(BuildContext context, Program p) async {
    final String? c = await showChoiceSheet(
      context,
      title: p.title,
      choices: <SheetChoice>[
        if (p.active)
          const SheetChoice(value: 'pause', label: 'Pause the program', key: ValueKey<String>('program-pause'))
        else
          const SheetChoice(value: 'resume', label: 'Resume the program', key: ValueKey<String>('program-resume')),
        if (p.status != 'done') const SheetChoice(value: 'end', label: 'End the program', key: ValueKey<String>('program-end')),
        const SheetChoice(value: 'delete', label: 'Delete the program', variant: OgVariant.dashed, key: ValueKey<String>('program-delete')),
      ],
    );
    if (c == null || !context.mounted) {
      return;
    }
    switch (c) {
      case 'pause':
        await _set(context, 'paused');
      case 'resume':
        await _set(context, 'active');
      case 'end':
        await _set(context, 'done');
      case 'delete':
        await _delete(context, p);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: deps.programs,
          builder: (BuildContext context, Widget? w) {
            final Program? p = deps.programs.byId(programId);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    OgIconButton(icon: Icons.chevron_left, onPressed: () => Navigator.of(context).pop()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p == null ? '' : programStatusLine(p),
                        key: const ValueKey<String>('program-status'),
                        style: OG.body(size: 16, weight: FontWeight.w700),
                      ),
                    ),
                    if (p != null)
                      KeyedSubtree(
                        key: const ValueKey<String>('program-menu'),
                        child: OgIconButton(icon: Icons.more_horiz, onPressed: () => _menu(context, p)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (p == null)
                  Text(deps.programs.loading ? 'Loading…' : 'This program is not here any more.', style: OG.muted())
                else ...<Widget>[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: KeyedSubtree(
                      key: const ValueKey<String>('program-change'),
                      child: SheetLink(label: 'Ask the coach to change it', onTap: () => _change(context, p)),
                    ),
                  ),
                  programView(p),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
