import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'set_check.dart';
import 'set_row.dart';

/// The current set, expanded: badge and title, "Last rep failed" pill, then
/// reps and weight steppers side by side.
class SetEditorCard extends StatelessWidget {
  const SetEditorCard({
    super.key,
    required this.number,
    required this.title,
    required this.reps,
    required this.kg,
    required this.failed,
    required this.onRepsChanged,
    required this.onKgChanged,
    required this.onFailedChanged,
    this.done = false,
    this.onCheck,
    this.checkKey,
  });

  final int number;
  final String title;
  final String reps;
  final String kg;
  final bool failed;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<double> onKgChanged;
  final ValueChanged<bool> onFailedChanged;
  final bool done;

  /// Tap on the check control; null hides the control.
  final VoidCallback? onCheck;
  final Key? checkKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 14),
      decoration: BoxDecoration(
        color: OG.ground,
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          top: BorderSide(color: OG.ink, width: 2),
          left: BorderSide(color: OG.ink, width: 2),
          right: BorderSide(color: OG.ink, width: 2),
          bottom: BorderSide(color: OG.ink, width: 5),
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              SetBadge(number: number, accent: true),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OG.body(size: 15, weight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _FailedPill(value: failed, onChanged: onFailedChanged),
                  ),
                ),
              ),
              if (onCheck != null) ...<Widget>[
                const SizedBox(width: 4),
                SetCheck(key: checkKey, done: done, onTap: onCheck!),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
            children: <Widget>[
              Expanded(
                child: NumberStepper(
                  value: reps,
                  unit: 'reps',
                  onMinus: () => onRepsChanged(-1),
                  onPlus: () => onRepsChanged(1),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: NumberStepper(
                  value: kg,
                  unit: 'kg',
                  onMinus: () => onKgChanged(-2.5),
                  onPlus: () => onKgChanged(2.5),
                ),
              ),
            ],
          ),
          ),
        ],
      ),
    );
  }
}

class _FailedPill extends StatelessWidget {
  const _FailedPill({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final Color fg = value ? OG.white : OG.ink;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onChanged(!value);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 5, 11, 5),
        decoration: BoxDecoration(
          color: value ? OG.ink : OG.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: OG.ink, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: fg,
            ),
            const SizedBox(width: 6),
            Text('Last rep failed',
                style: OG.body(size: 13, weight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// A value with a minus and a plus button. A long press on a button calls
/// the optional [onLongMinus] or [onLongPlus] (a larger step).
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.value,
    required this.unit,
    required this.onMinus,
    required this.onPlus,
    this.onLongMinus,
    this.onLongPlus,
    this.onValueTap,
  });

  /// Tap on the value itself (for example to type one). Null: the value is not a control.
  final VoidCallback? onValueTap;

  final String value;
  final String unit;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback? onLongMinus;
  final VoidCallback? onLongPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        StepperButton(icon: Icons.remove, onTap: onMinus, onLongPress: onLongMinus),
        Expanded(
          child: GestureDetector(
            key: onValueTap == null ? null : const ValueKey<String>('stepper-value'),
            behavior: HitTestBehavior.opaque,
            onTap: onValueTap,
            child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value,
                      style: OG
                          .display(34)
                          .copyWith(height: 1, letterSpacing: -1)),
                ),
                Text(
                  unit.toUpperCase(),
                  style: OG
                      .body(size: 11, weight: FontWeight.w600, color: OG.mute)
                      .copyWith(height: 1.2, letterSpacing: 0.5),
                ),
              ],
            ),
            ),
          ),
        ),
        StepperButton(icon: Icons.add, onTap: onPlus, onLongPress: onLongPlus),
      ],
    );
  }
}

class StepperButton extends StatelessWidget {
  const StepperButton({super.key, required this.icon, required this.onTap, this.onLongPress});

  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      onLongPress: onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              onLongPress!();
            },
      child: Container(
        width: 42,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: OG.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OG.ink, width: 2),
        ),
        child: Icon(icon, size: 22, color: OG.ink),
      ),
    );
  }
}
