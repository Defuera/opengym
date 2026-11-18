import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/preparing_card.dart';
import 'session_screen.dart';

/// Asks the server for the stored plan of the activity + focus (at most a few
/// seconds), then opens the session.
/// "Use my last session" skips the wait and uses the local planner.
class PrepareSessionScreen extends StatefulWidget {
  const PrepareSessionScreen({
    super.key,
    required this.deps,
    this.activity = gymType,
    this.focus,
  });

  final AppDeps deps;

  /// The activity name of the proposal.
  final String activity;

  /// The advised focus from the start sheet. Null: the server picks it.
  final String? focus;

  @override
  State<PrepareSessionScreen> createState() => _PrepareSessionScreenState();
}

class _PrepareSessionScreenState extends State<PrepareSessionScreen> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Plan? p = await widget.deps.plans.fetchNext(activity: widget.activity, focus: widget.focus);
    _go(p);
  }

  void _go(Plan? plan) {
    if (_done || !mounted) {
      return;
    }
    _done = true;
    final AppDeps d = widget.deps;
    final String? focus = widget.focus ?? plan?.focus;
    if (plan != null) {
      d.store.begin(
        activity: widget.activity,
        focus: focus,
        prepared: d.plans.exercisesFor(plan),
        rationale: plan.rationale,
      );
    } else {
      d.store.begin(activity: widget.activity, focus: focus);
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => SessionScreen(store: d.store, deps: d),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? focus = widget.focus;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  OgIconButton(
                    icon: Icons.chevron_left,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (focus != null)
                          Text(
                            focus,
                            style: OG.muted(size: 14, weight: FontWeight.w600),
                          ),
                        Text(widget.activity, style: OG.display(32)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              PreparingCard(
                title: 'Preparing your session…',
                message: 'Looking at your log and goals. This can take a few seconds.',
                actionLabel: 'Use my last session',
                onAction: () => _go(null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
