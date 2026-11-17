import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../stores/start_draft.dart';
import '../widgets/og_sheet.dart';
import '../widgets/segmented_toggle.dart';
import 'log_sheet.dart';
import 'start_sheet.dart';

/// The Home plus: one bottom sheet with a switch "Start session" | "Log".
/// [initial] is the tab shown first (0 = Start session, 1 = Log).
Future<void> showPlusSheet(BuildContext context, AppDeps deps, {int initial = 0}) {
  final NavigatorState nav = Navigator.of(context);
  return showOgSheet<void>(
    context,
    (BuildContext c) => PlusSheet(deps: deps, nav: nav, initial: initial),
    scroll: false,
  );
}

Future<void> showStartSheet(BuildContext context, AppDeps deps) => showPlusSheet(context, deps);

Future<void> showLogSheet(BuildContext context, AppDeps deps) => showPlusSheet(context, deps, initial: 1);

class PlusSheet extends StatefulWidget {
  const PlusSheet({super.key, required this.deps, required this.nav, this.initial = 0});

  final AppDeps deps;

  /// The navigator under the sheet: the sheet closes, then the next screen opens.
  final NavigatorState nav;
  final int initial;

  @override
  State<PlusSheet> createState() => _PlusSheetState();
}

class _PlusSheetState extends State<PlusSheet> {
  // The Start form and the Log text live here, so a switch of tab keeps what was typed.
  final StartDraft _start = StartDraft();
  final TextEditingController _log = TextEditingController();
  late int _tab = widget.initial;
  bool _preparing = false;

  @override
  void dispose() {
    _start.dispose();
    _log.dispose();
    super.dispose();
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
            selectedIndex: _tab,
            onChanged: (int i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 14),
        ],
        Flexible(
          child: _tab == 0
              ? StartSheet(
                  deps: widget.deps,
                  nav: widget.nav,
                  draft: _start,
                  onPreparing: (bool b) => setState(() => _preparing = b),
                )
              : LogSheet(deps: widget.deps, nav: widget.nav, controller: _log),
        ),
      ],
    );
  }
}
