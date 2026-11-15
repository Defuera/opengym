import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../planner.dart';
import '../stores/goals_store.dart';
import '../theme.dart';
import '../widgets/cta_button.dart';
import '../widgets/goal_row.dart';
import '../widgets/note_box.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import 'goal_form_sheet.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, required this.deps});

  final AppDeps deps;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  @override
  void initState() {
    super.initState();
    widget.deps.goals.load();
  }

  Future<void> _add() async {
    final GoalDraft? d = await showGoalForm(context);
    if (d == null) {
      return;
    }
    await widget.deps.goals.add(
      title: d.title,
      kind: d.kind,
      exercise: d.exercise,
      targetKg: d.targetKg,
      sessionsPerWeek: d.sessionsPerWeek,
    );
  }

  String _detail(Goal g) {
    final List<String> parts = <String>[goalKindLabel(g.kind)];
    if (g.exercise != null) {
      parts.add(g.exercise!);
    }
    if (g.targetKg != null) {
      parts.add('${fmtKg(g.targetKg!)} kg');
    }
    if (g.sessionsPerWeek != null) {
      parts.add('${g.sessionsPerWeek} / week');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final GoalsStore goals = widget.deps.goals;
    return ListenableBuilder(
      listenable: goals,
      builder: (BuildContext context, Widget? child) {
        final List<Widget> rows = <Widget>[];
        for (final Goal g in goals.goals) {
          rows.add(GoalRow(
            title: g.title,
            detail: _detail(g),
            done: g.done,
            onToggleDone: () => goals.markDone(g),
            onDelete: () => goals.remove(g),
          ));
          rows.add(const SizedBox(height: 10));
        }
        final String? err = goals.error;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          OgIconButton(
                            icon: Icons.chevron_left,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text('Goals', style: OG.display(32))),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (err != null) ...<Widget>[
                        NoteBox(title: 'Goals are not available.', message: err),
                        const SizedBox(height: 12),
                        OgButton(onPressed: goals.load, child: const Text('Try again')),
                        const SizedBox(height: 18),
                      ],
                      if (goals.loading && goals.goals.isEmpty)
                        Text('Loading…', style: OG.muted())
                      else if (goals.goals.isEmpty && err == null)
                        const NoteBox(
                          title: 'No goals yet.',
                          message: 'Add one, or tell the coach in chat.',
                        ),
                      ...rows,
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: CtaButton(
                    label: 'Add goal',
                    icon: Icons.add,
                    variant: OgVariant.accent,
                    onPressed: _add,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
