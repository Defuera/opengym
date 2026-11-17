import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../stores/plan_store.dart';
import '../stores/start_draft.dart';
import '../stores/start_run.dart';
import '../theme.dart';
import '../widgets/preparing_card.dart';
import '../widgets/proposal_row.dart';
import '../widgets/sheet_link.dart';
import '../widgets/new_kind_row.dart';
import '../widgets/start_form.dart';
import 'start_flow.dart';

class StartSheet extends StatefulWidget {
  const StartSheet({
    super.key,
    required this.deps,
    required this.nav,
    required this.draft,
    required this.onPreparing,
  });

  /// Kept by the sheet, so typed text and the open form survive a switch to the Log tab.
  final StartDraft draft;

  /// Tells the sheet a request is running (the tab switch is hidden then).
  final ValueChanged<bool> onPreparing;

  final AppDeps deps;

  /// The navigator under the sheet: the sheet closes, then the session opens.
  final NavigatorState nav;

  @override
  State<StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends State<StartSheet> {
  StartDraft get _draft => widget.draft;
  StartRun? _run;
  String _typed = '';

  @override
  void dispose() {
    _run?.cancel();
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

  /// An empty session. [name] is used as it is (the form limits it to 40).
  void _empty([String name = gymType]) {
    _run?.cancel();
    widget.nav.pop();
    openEmpty(widget.nav, widget.deps, activity: name);
  }

  Future<void> _prepare() async {
    final String t = _draft.effectiveName;
    if (t.isEmpty || _run != null) {
      return;
    }
    // A request is not a fact and never waits in the outbox: offline, go on.
    if (!widget.deps.connection.connected) {
      _empty(t);
      return;
    }
    final String wish = _draft.wish.text.trim();
    final StartRun run = widget.deps.plans.requestStart(name: t, text: wish.isEmpty ? null : wish);
    setState(() {
      _run = run;
      _typed = t;
    });
    widget.onPreparing(true);
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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
      listenable: Listenable.merge(<Listenable>[widget.deps.store, widget.deps.plans, _draft]),
      builder: (BuildContext context, Widget? child) {
        if (_draft.open) {
          return StartForm(
            name: _draft.name,
            wish: _draft.wish,
            lockedName: _draft.locked,
            onBack: _draft.close,
            onPrepare: _prepare,
            onStartEmpty: () => _empty(_draft.effectiveName),
          );
        }
        final List<Prediction> list = _proposals();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              list.isEmpty
                  ? 'Name a session. The coach prepares it.'
                  : 'The coach prepares it. Most likely first, from your log.',
              style: OG.muted(),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 4),
                children: <Widget>[
                  for (int i = 0; i < list.length; i++) ...<Widget>[
                    ProposalRow(
                      title: _title(list[i]),
                      subtitle: list[i].reason,
                      primary: i == 0,
                      onTap: () => _choose(list[i]),
                      onAsk: () => _draft.openFor(list[i].type),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            NewKindRow(label: 'New kind of session', onTap: _draft.openNew),
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
