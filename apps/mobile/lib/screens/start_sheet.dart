import 'package:flutter/material.dart';

import '../activity_log.dart';
import '../app/deps.dart';
import '../models.dart';
import '../planner.dart';
import '../stores/start_draft.dart';
import '../stores/start_run.dart';
import '../theme.dart';
import '../widgets/new_kind_row.dart';
import '../widgets/preparing_card.dart';
import '../widgets/proposal_row.dart';
import '../widgets/sheet_link.dart';
import '../widgets/start_details.dart';
import '../widgets/start_other.dart';
import 'start_flow.dart';

/// The Start tab: step 1 lists the activity types of the log, step 2 takes an
/// optional note and starts. The user chooses the activity; the coach decides
/// the content (ADR-016).
class StartSheet extends StatefulWidget {
  const StartSheet({
    super.key,
    required this.deps,
    required this.nav,
    required this.draft,
    required this.onPreparing,
  });

  /// Kept by the sheet, so typed text and the open step survive a switch to the Log tab.
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
  bool _more = false;

  @override
  void dispose() {
    _run?.cancel();
    super.dispose();
  }

  /// An empty session. [name] is used as it is (the draft limits it to 40).
  void _empty([String name = gymType, StartFallback? fallback]) {
    _run?.cancel();
    widget.nav.pop();
    openEmpty(widget.nav, widget.deps, activity: name, fallback: fallback);
  }

  /// The plain-code plan for [name]: the focus due in the log, then the last
  /// session of that focus. Used offline and when the request fails.
  void _rules(String name, [StartFallback? fallback]) {
    _run?.cancel();
    final List<FocusRank> rot = focusRotation(widget.deps.store.sessions, activity: name);
    final String? focus = rot.isEmpty ? null : rot.first.focus;
    widget.nav.pop();
    openPrepared(widget.nav, widget.deps,
        activity: name,
        focus: focus,
        local: true,
        fallback: fallback == null || focus == null
            ? fallback
            : StartFallback(
                notice: '${fallback.notice} This is your last $focus session.', note: fallback.note, late: fallback.late));
  }

  Future<void> _start() async {
    final String t = _draft.type;
    final String note = _draft.note.text.trim();
    if (t.isNotEmpty) {
      await _request(name: t, text: note.isEmpty ? null : note, fallback: t, rules: true);
    }
  }

  /// "Other": the free text alone; the coach names the activity.
  Future<void> _startOther() async {
    final String text = _draft.otherText.text.trim();
    if (text.isNotEmpty) {
      await _request(text: text, fallback: activityNameFromText(text));
    }
  }

  /// Sends one start request and opens the proposal. Offline or on failure the
  /// session of [fallback] opens: with [rules] the plain-code plan of that
  /// activity, otherwise an empty session.
  Future<void> _request({String? name, String? text, required String fallback, bool rules = false}) async {
    if (_run != null) {
      return;
    }
    void plain([StartFallback? why]) => rules ? _rules(fallback, why) : _empty(fallback, why);
    // A request is not a fact and never waits in the outbox: offline, go on.
    if (!widget.deps.connection.connected) {
      plain();
      return;
    }
    final StartRun run = widget.deps.plans.requestStart(name: name, text: text);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _run = run;
      _typed = fallback;
    });
    widget.onPreparing(true);
    final StartProposal? p = await run.result;
    if (!mounted) {
      return;
    }
    if (p == null) {
      // The person must see that this is not the coach's plan. A run that gave
      // up keeps waiting: the session screen offers a late answer.
      if (run.gaveUp) {
        _run = null;
      }
      plain(StartFallback(
        notice: run.gaveUp ? 'The coach did not answer in time.' : 'The coach could not build a session.',
        note: text,
        late: run.gaveUp ? run : null,
      ));
      return;
    }
    widget.nav.pop();
    openProposal(widget.nav, widget.deps, p, requestId: run.requestId);
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
      listenable: Listenable.merge(<Listenable>[widget.deps.store, _draft]),
      builder: (BuildContext context, Widget? child) {
        switch (_draft.step) {
          case StartStep.details:
            return StartDetails(
              title: _draft.type,
              note: _draft.note,
              onBack: _draft.back,
              onStart: _start,
            );
          case StartStep.other:
            return StartOther(
              text: _draft.otherText,
              onBack: _draft.back,
              onStart: _startOther,
            );
          case StartStep.types:
            return _types();
        }
      },
    );
  }

  Widget _types() {
    // A log type that is itself named "Other" is left out: "Other" here is the free text.
    final List<StartType> all = startTypes(widget.deps.store.sessions)
        .where((StartType x) => activityKey(x.name) != 'other')
        .toList();
    final (List<StartType> shown, List<StartType> rest) =
        splitCurrent<StartType>(all, (StartType x) => usedRecently(x.lastWhen));
    final List<StartType> types = _more ? <StartType>[...shown, ...rest] : shown;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          types.isEmpty ? 'Nothing in your log yet.' : 'What are you doing?',
          style: OG.muted(),
        ),
        const SizedBox(height: 14),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 4),
            children: <Widget>[
              for (int i = 0; i < types.length; i++) ...<Widget>[
                ProposalRow(
                  title: types[i].name,
                  primary: i == 0,
                  onTap: () => _draft.pick(types[i].name),
                ),
                const SizedBox(height: 10),
              ],
              if (!_more && rest.isNotEmpty) ...<Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: SheetLink(label: 'More from your log', onTap: () => setState(() => _more = true)),
                ),
                const SizedBox(height: 10),
              ],
              NewKindRow(label: 'Other', onTap: _draft.openOther),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: SheetLink(label: 'Start empty, without a plan', onTap: _empty),
        ),
      ],
    );
  }
}
