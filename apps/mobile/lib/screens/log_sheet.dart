import 'package:flutter/material.dart';

import '../activity_log.dart';
import '../app/deps.dart';
import '../theme.dart';
import '../widgets/og_sheet.dart';
import '../widgets/proposal_row.dart';
import '../widgets/sheet_link.dart';
import '../widgets/something_new_box.dart';
import 'import_screen.dart';
import 'other_activity_screen.dart';

/// Home "Log": the time/distance activities from the log (most often first),
/// one free-text "Something new", and the import link. No AI call.
Future<void> showLogSheet(BuildContext context, AppDeps deps) {
  final NavigatorState nav = Navigator.of(context);
  return showOgSheet<void>(context, (BuildContext c) => LogSheet(deps: deps, nav: nav));
}

class LogSheet extends StatefulWidget {
  const LogSheet({super.key, required this.deps, required this.nav});

  final AppDeps deps;
  final NavigatorState nav;

  @override
  State<LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<LogSheet> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Log', style: OG.display(32)),
        const SizedBox(height: 6),
        Text(
          items.isEmpty
              ? 'Record what you did.'
              : 'Record what you did. Most often first, from your log.',
          style: OG.muted(),
        ),
        const SizedBox(height: 16),
        for (final LogActivity a in items) ...<Widget>[
          ProposalRow(title: a.name, subtitle: a.lastLine(), onTap: () => _log(a.name)),
          const SizedBox(height: 10),
        ],
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
