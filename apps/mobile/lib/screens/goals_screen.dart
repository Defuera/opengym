import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../planner.dart';
import '../stores/connection_store.dart';
import '../stores/goals_store.dart';
import '../theme.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/cta_button.dart';
import '../widgets/goal_row.dart';
import '../widgets/note_box.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import 'part_chat.dart';

String _kindLabel(String kind) {
  switch (kind) {
    case 'strength':
      return 'Strength';
    case 'consistency':
      return 'Consistency';
    default:
      return 'Custom';
  }
}

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, required this.deps});

  final AppDeps deps;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  /// A new goal, and a change of one, are a chat (ADR-032, step D): the coach
  /// drafts the goal, the person presses Done. Done and delete stay exact taps.
  Future<void> _add() => openGoalChat(Navigator.of(context), widget.deps);

  Future<void> _edit(Goal g) => openGoalChat(Navigator.of(context), widget.deps, change: g);

  Future<void> _delete(Goal g) async {
    final bool ok = await confirmDelete(context, title: 'Delete this goal?', label: 'Delete goal');
    if (ok && mounted) {
      await widget.deps.goals.remove(g);
    }
  }

  String _detail(Goal g) {
    final List<String> parts = <String>[_kindLabel(g.kind)];
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
    final ConnectionStore conn = widget.deps.connection;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[goals, conn]),
      builder: (BuildContext context, Widget? child) {
        final List<Widget> rows = <Widget>[];
        for (final Goal g in goals.goals) {
          rows.add(GoalRow(
            title: g.title,
            detail: _detail(g),
            done: g.done,
            onToggleDone: () => goals.markDone(g),
            onDelete: () => _delete(g),
            onTap: () => _edit(g),
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
                        const SizedBox(height: 18),
                      ],
                      if (goals.loading && goals.goals.isEmpty && err == null)
                        (conn.connected
                            ? Text('Loading…', style: OG.muted())
                            : NoteBox(
                                title: 'Goals load when you are connected.',
                                message: conn.error ?? 'Not connected.',
                              ))
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
