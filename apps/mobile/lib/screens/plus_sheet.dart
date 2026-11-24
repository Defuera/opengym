import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../stores/start_draft.dart';
import '../widgets/og_sheet.dart';
import '../widgets/segmented_toggle.dart';
import 'log_chat.dart';
import 'start_sheet.dart';

/// The Home plus: one bottom sheet with a switch "Start session" | "Log".
/// Start session shows the Start steps. Log has no content of its own: choosing
/// it closes the sheet and opens the log chat in a new thread.
Future<void> showPlusSheet(BuildContext context, AppDeps deps) {
  final NavigatorState nav = Navigator.of(context);
  return showOgSheet<void>(
    context,
    (BuildContext c) => PlusSheet(deps: deps, nav: nav),
    scroll: false,
  );
}

class PlusSheet extends StatefulWidget {
  const PlusSheet({super.key, required this.deps, required this.nav});

  final AppDeps deps;

  /// The navigator under the sheet: the sheet closes, then the next screen opens.
  final NavigatorState nav;

  @override
  State<PlusSheet> createState() => _PlusSheetState();
}

class _PlusSheetState extends State<PlusSheet> {
  // The Start form lives here, so a step change keeps what was typed.
  final StartDraft _start = StartDraft();
  bool _preparing = false;

  @override
  void dispose() {
    _start.dispose();
    super.dispose();
  }

  void _openLog() {
    final NavigatorState nav = widget.nav;
    final AppDeps deps = widget.deps;
    nav.pop(); // the sheet
    openLogChat(nav, deps);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!_preparing) ...<Widget>[
          SegmentedToggle(
            labels: const <String>['Start session', 'Log'],
            selectedIndex: 0,
            onChanged: (int i) {
              if (i == 1) {
                _openLog();
              }
            },
          ),
          const SizedBox(height: 14),
        ],
        Flexible(
          child: StartSheet(
            deps: widget.deps,
            nav: widget.nav,
            draft: _start,
            onPreparing: (bool b) => setState(() => _preparing = b),
          ),
        ),
      ],
    );
  }
}
