import 'package:flutter/material.dart';

import '../models.dart';
import '../planner.dart';
import '../stores/plan_store.dart';
import '../store.dart';
import '../widgets/focus_chips.dart';

/// Chips to change the focus of the open gym session before the first set is
/// done. A pick swaps in the stored plan of that focus (no AI call), or the
/// local plan when offline or when the server has none.
class SessionFocusBar extends StatefulWidget {
  const SessionFocusBar({
    super.key,
    required this.store,
    required this.plans,
    required this.online,
    this.advised,
  });

  final AppStore store;
  final PlanStore plans;
  final bool online;

  /// The focus the server or the local rotation advised for this start.
  final String? advised;

  @override
  State<SessionFocusBar> createState() => _SessionFocusBarState();
}

class _SessionFocusBarState extends State<SessionFocusBar> {
  /// Fixed at the start: picking another chip must not move the "advised" mark.
  late final String? _advised = widget.advised ?? widget.store.active?.focus;

  Future<void> _pick(String focus) async {
    Plan? plan;
    if (widget.online) {
      plan = await widget.plans.fetchNext(activity: widget.store.active?.type, focus: focus);
    }
    if (!mounted) {
      return;
    }
    widget.store.changeFocus(
      focus,
      prepared: plan == null ? null : widget.plans.exercisesFor(plan),
      rationale: plan?.rationale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Session? a = widget.store.active;
    if (a == null || a.kind != 'gym' || widget.store.hasDoneSet) {
      return const SizedBox.shrink();
    }
    final String? advised = _advised;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: FocusChips(
        foci: gymFoci(widget.store.sessions, activity: a.type, advised: advised),
        selected: a.focus,
        advised: advised,
        onSelect: _pick,
      ),
    );
  }
}
