import 'package:flutter/material.dart';

import '../activity_log.dart';
import '../app/deps.dart';
import '../theme.dart';
import '../widgets/note_tile.dart';
import '../widgets/proposal_row.dart';
import '../widgets/sheet_link.dart';
import '../widgets/something_new_box.dart';
import 'entry_form_screen.dart';
import 'import_screen.dart';
import 'log_text_screen.dart';

class LogSheet extends StatefulWidget {
  const LogSheet({
    super.key,
    required this.deps,
    required this.nav,
    required this.controller,
  });

  /// Kept by the sheet, so typed text survives a switch to the Start tab.
  final TextEditingController controller;

  final AppDeps deps;
  final NavigatorState nav;

  @override
  State<LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<LogSheet> {
  TextEditingController get _text => widget.controller;
  bool _more = false;

  @override
  void dispose() {
    super.dispose();
  }

  void _log(String name) {
    final String n = name.trim();
    if (n.isEmpty) {
      return;
    }
    widget.nav.pop();
    widget.nav.push(MaterialPageRoute<void>(
      builder: (BuildContext c) => LogTextScreen(
        deps: widget.deps,
        activity: n.length > 40 ? n.substring(0, 40).trim() : n,
      ),
    ));
  }

  /// The sheet closes and the note form opens; with a camera or library start
  /// the picker opens at once, so a photo note is: tile, photo, Save.
  void _note(EntryStart start) {
    widget.nav.pop();
    widget.nav.push(MaterialPageRoute<bool>(
      builder: (BuildContext c) => EntryFormScreen(deps: widget.deps, start: start),
    ));
  }

  void _import() {
    widget.nav.pop();
    widget.nav.push(MaterialPageRoute<void>(
      builder: (BuildContext c) => ImportScreen(deps: widget.deps),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final List<LogActivity> all = logActivities(widget.deps.store.sessions);
    final (List<LogActivity> shown, List<LogActivity> rest) =
        splitCurrent<LogActivity>(all, (LogActivity a) => usedRecently(a.last.when));
    final List<LogActivity> items = _more ? <LogActivity>[...shown, ...rest] : shown;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('A note: a meal, how you feel, anything.', style: OG.muted()),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: NoteTile(
                key: const ValueKey<String>('note-camera'),
                icon: Icons.photo_camera_outlined,
                label: 'Camera',
                primary: true,
                onTap: () => _note(EntryStart.camera),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: NoteTile(
                key: const ValueKey<String>('note-library'),
                icon: Icons.photo_library_outlined,
                label: 'Photo',
                onTap: () => _note(EntryStart.library),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: NoteTile(
                key: const ValueKey<String>('note-text'),
                icon: Icons.edit_outlined,
                label: 'Text',
                onTap: () => _note(EntryStart.text),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('A session you did.', style: OG.muted()),
        const SizedBox(height: 10),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 4),
            children: <Widget>[
              for (final LogActivity a in items) ...<Widget>[
                ProposalRow(title: a.name, subtitle: a.lastLine(), onTap: () => _log(a.name)),
                const SizedBox(height: 10),
              ],
              if (!_more && rest.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SheetLink(label: 'More from your log', onTap: () => setState(() => _more = true)),
                ),
            ],
          ),
        ),
        SomethingNewBox(
          controller: _text,
          hint: 'Something new: "padel"',
          buttonLabel: 'Log',
          onSubmit: () => _log(_text.text),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: SheetLink(label: 'Import old training data', onTap: _import),
        ),
      ],
    );
  }
}
