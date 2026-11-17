import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../stores/plan_store.dart';
import '../stores/start_run.dart';
import '../theme.dart';
import '../widgets/og_sheet.dart';
import '../widgets/preparing_card.dart';
import '../widgets/proposal_row.dart';
import '../widgets/sheet_link.dart';
import '../widgets/something_new_box.dart';
import 'start_flow.dart';

/// Home "Start session": stored proposals of sessions with sets, one free-text
/// "Something new", and "Start empty, without a plan".
Future<void> showStartSheet(BuildContext context, AppDeps deps) {
  final NavigatorState nav = Navigator.of(context);
  return showOgSheet<void>(context, (BuildContext c) => StartSheet(deps: deps, nav: nav));
}

class StartSheet extends StatefulWidget {
  const StartSheet({super.key, required this.deps, required this.nav});

  final AppDeps deps;

  /// The navigator under the sheet: the sheet closes, then the session opens.
  final NavigatorState nav;

  @override
  State<StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends State<StartSheet> {
  final TextEditingController _text = TextEditingController();
  StartRun? _run;
  String _typed = '';

  @override
  void dispose() {
    _run?.cancel();
    _text.dispose();
    super.dispose();
  }

  List<Prediction> _proposals() {
    final AppDeps d = widget.deps;
    final List<Prediction> all =
        d.connection.connected ? d.plans.predictionsFor(d.store.sessions) : localPredictions(d.store.sessions);
    return all.where((Prediction p) => p.kind == 'gym').take(6).toList();
  }

  void _choose(Prediction p) {
    widget.nav.pop();
    openPrepared(widget.nav, widget.deps, activity: p.type, focus: p.focus);
  }

  void _empty([String? text]) {
    _run?.cancel();
    widget.nav.pop();
    openEmpty(
      widget.nav,
      widget.deps,
      activity: text == null ? gymType : activityNameFromText(text),
    );
  }

  Future<void> _prepare() async {
    final String t = _text.text.trim();
    if (t.isEmpty || _run != null) {
      return;
    }
    // A request is not a fact and never waits in the outbox: offline, go on.
    if (!widget.deps.connection.connected) {
      _empty(t);
      return;
    }
    final StartRun run = widget.deps.plans.requestStart(t);
    setState(() {
      _run = run;
      _typed = t;
    });
    final StartProposal? p = await run.result;
    if (!mounted) {
      return;
    }
    if (p == null) {
      _empty(t);
      return;
    }
    widget.nav.pop();
    openProposal(widget.nav, widget.deps, p);
  }

  @override
  Widget build(BuildContext context) {
    if (_run != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Start session', style: OG.display(32)),
          const SizedBox(height: 16),
          PreparingCard(
            title: 'Preparing…',
            message: 'The coach shapes a session for "$_typed". It opens when ready.',
            actionLabel: 'Start empty now',
            onAction: () => _empty(_typed),
          ),
          const SizedBox(height: 8),
        ],
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[widget.deps.store, widget.deps.plans]),
      builder: (BuildContext context, Widget? child) {
        final List<Prediction> list = _proposals();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Start session', style: OG.display(32)),
            const SizedBox(height: 6),
            Text(
              list.isEmpty
                  ? 'Say what you want to do. The coach prepares it.'
                  : 'The coach prepares it. Most likely first, from your log.',
              style: OG.muted(),
            ),
            const SizedBox(height: 16),
            for (int i = 0; i < list.length; i++) ...<Widget>[
              ProposalRow(
                title: _title(list[i]),
                subtitle: list[i].reason,
                primary: i == 0,
                onTap: () => _choose(list[i]),
              ),
              const SizedBox(height: 10),
            ],
            SomethingNewBox(
              controller: _text,
              hint: 'Something new: "hotel gym, 30 min"',
              buttonLabel: 'Prepare',
              onSubmit: _prepare,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: SheetLink(label: 'Start empty, without a plan', onTap: _empty),
            ),
          ],
        );
      },
    );
  }

  String _title(Prediction p) {
    final String f = p.focus ?? '';
    return f.isEmpty ? p.type : '${p.type} · $f';
  }
}
