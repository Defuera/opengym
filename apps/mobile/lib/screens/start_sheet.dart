import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../stores/plan_store.dart';
import '../stores/start_draft.dart';
import '../stores/start_run.dart';
import '../widgets/preparing_card.dart';
import '../widgets/sheet_link.dart';
import '../widgets/new_kind_row.dart';
import '../widgets/labeled_field.dart';
import '../widgets/og_button.dart';
import '../widgets/start_form.dart';
import '../widgets/today_card.dart';
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
  bool _today = false;

  @override
  void dispose() {
    _run?.cancel();
    super.dispose();
  }

  /// The coach's pick for today: the top gym prediction, or null.
  Prediction? _pick() {
    final AppDeps d = widget.deps;
    final List<Prediction> all = d.connection.connected
        ? d.plans.predictionsFor(d.store.sessions)
        : localPredictions(d.store.sessions);
    for (final Prediction p in all) {
      if (p.kind == 'gym') {
        return p;
      }
    }
    return null;
  }

  /// The shown pick as a plan to open, or an empty session when there is none.
  void _fallback(Prediction? pick) {
    if (pick == null) {
      _empty();
      return;
    }
    _run?.cancel();
    widget.nav.pop();
    openPrepared(widget.nav, widget.deps,
        activity: pick.type, focus: pick.focus);
  }

  Future<void> _startToday() async {
    if (_run != null) {
      return;
    }
    final Prediction? pick = _pick();
    // A request is not a fact and never waits in the outbox: offline, go on.
    if (!widget.deps.connection.connected) {
      _fallback(pick);
      return;
    }
    final String wish = _draft.today.text.trim();
    final String focus = (pick?.focus ?? '').trim();
    final StartRun run = widget.deps.plans.requestStart(
      today: true,
      text: wish.isEmpty ? null : wish,
      hintType: pick?.type,
      hintFocus: focus.isEmpty ? null : focus,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _run = run;
      _today = true;
    });
    widget.onPreparing(true);
    final StartProposal? p = await run.result;
    if (!mounted) {
      return;
    }
    if (p == null) {
      _fallback(pick);
      return;
    }
    widget.nav.pop();
    openProposal(widget.nav, widget.deps, p);
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
    final StartRun run = widget.deps.plans
        .requestStart(name: t, text: wish.isEmpty ? null : wish);
    setState(() {
      _run = run;
      _typed = t;
      _today = false;
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
            message: _today
                ? "The coach shapes today's session. It opens when ready."
                : 'The coach shapes a session for "$_typed". It opens when ready.',
            actionLabel: 'Start empty now',
            onAction: () => _empty(_today ? gymType : _typed),
          ),
          const SizedBox(height: 8),
        ],
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge(
          <Listenable>[widget.deps.store, widget.deps.plans, _draft]),
      builder: (BuildContext context, Widget? child) {
        if (_draft.open) {
          return StartForm(
            name: _draft.name,
            wish: _draft.wish,
            onBack: _draft.close,
            onPrepare: _prepare,
            onStartEmpty: () => _empty(_draft.effectiveName),
          );
        }
        final Prediction? pick = _pick();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      TodayCard(
                          title: pick == null ? null : _title(pick),
                          reason: pick?.reason ?? ''),
                      const SizedBox(height: 14),
                      LabeledField(
                        label: 'Anything for today? (optional)',
                        controller: _draft.today,
                        hint: 'Short on time, go easy, left hand is sore…',
                        maxLength: 200,
                        minLines: 2,
                        maxLines: 4,
                        autocorrect: true,
                        keyboardType: TextInputType.multiline,
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
            ),
            OgButton(
              variant: OgVariant.accent,
              onPressed: _startToday,
              child: const Text("Start today's session"),
            ),
            const SizedBox(height: 10),
            NewKindRow(label: 'New kind of session', onTap: _draft.openNew),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: SheetLink(
                  label: 'Start empty, without a plan', onTap: _empty),
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
