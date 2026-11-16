import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/preparing_card.dart';
import 'session_screen.dart';

/// Asks the server for the next plan (at most 12 s), then opens the session.
/// "Use my last session" skips the wait and uses the local planner.
class PrepareSessionScreen extends StatefulWidget {
  const PrepareSessionScreen({super.key, required this.deps, required this.type});

  final AppDeps deps;
  final String type;

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
    final Plan? p = await widget.deps.plans.fetchNext(widget.type);
    _go(p);
  }

  void _go(Plan? plan) {
    if (_done || !mounted) {
      return;
    }
    _done = true;
    final AppDeps d = widget.deps;
    if (plan != null) {
      d.store.begin(
        widget.type,
        prepared: d.plans.exercisesFor(plan),
        rationale: plan.rationale,
      );
    } else {
      d.store.begin(widget.type);
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => SessionScreen(store: d.store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    child: Text('Gym · ${widget.type}', style: OG.display(32)),
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
