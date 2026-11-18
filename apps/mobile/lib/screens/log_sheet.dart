import 'package:flutter/material.dart';

import '../activity_log.dart';
import '../app/deps.dart';
import '../theme.dart';
import '../widgets/proposal_row.dart';
import '../widgets/sheet_link.dart';
import '../widgets/something_new_box.dart';
import 'entry_form_screen.dart';
import 'import_screen.dart';
import 'other_activity_screen.dart';

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
      builder: (BuildContext c) => OtherActivityScreen(
        store: widget.deps.store,
        activity: n.length > 40 ? n.substring(0, 40).trim() : n,
      ),
    ));
  }

  void _note() {
    widget.nav.pop();
    widget.nav.push(MaterialPageRoute<bool>(
      builder: (BuildContext c) => EntryFormScreen(deps: widget.deps),
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
    final List<LogActivity> items = logActivities(widget.deps.store.sessions);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ProposalRow(
          title: 'Note',
          subtitle: 'A meal, a photo, anything.',
          primary: true,
          onTap: _note,
        ),
        const SizedBox(height: 14),
        Text(
          items.isEmpty
              ? 'Record what you did.'
              : 'Record what you did. Most often first, from your log.',
          style: OG.muted(),
        ),
        const SizedBox(height: 14),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 4),
            children: <Widget>[
              for (final LogActivity a in items) ...<Widget>[
                ProposalRow(title: a.name, subtitle: a.lastLine(), onTap: () => _log(a.name)),
                const SizedBox(height: 10),
              ],
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
          child: SheetLink(label: 'Import a photo or a file', onTap: _import),
        ),
      ],
    );
  }
}
