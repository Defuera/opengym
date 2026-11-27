import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'set_entry.dart';
import 'text_sheet.dart';
import 'set_check.dart';
import 'set_row.dart';

/// The current set, expanded: badge, title and check; reps and weight steppers
/// side by side; then a quiet "Last rep failed" toggle. No weight shows as
/// "BW" (bodyweight); the plus still adds weight.
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
    this.onRepsSet,
    this.onKgSet,
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

  /// A typed value (tap on the number). Null: the number is not a control.
  /// A text that is not a valid number changes nothing.
  final ValueChanged<int>? onRepsSet;
  final ValueChanged<double>? onKgSet;

  Future<void> _typeReps(BuildContext context) async {
    final String? text = await showTextSheet(
      context,
      title: 'Reps',
      label: 'Number of reps',
      hint: '12',
      actionLabel: 'Set',
      initialText: reps,
      keyboardType: TextInputType.number,
    );
    final int? v = text == null ? null : parseRepsEntry(text);
    if (v != null) {
      onRepsSet?.call(v);
    }
  }

  Future<void> _typeKg(BuildContext context) async {
    final String? text = await showTextSheet(
      context,
      title: 'Weight',
      label: 'Kilograms (0 is bodyweight)',
      hint: '4 or 2,5',
      actionLabel: 'Set',
      initialText: isZeroKg(kg) ? '0' : kg,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    final double? v = text == null ? null : parseKgEntry(text);
    if (v != null) {
      onKgSet?.call(v);
    }
  }

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
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OG.body(size: 15, weight: FontWeight.w800),
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
                  onRepeatMinus: () => onRepsChanged(-10),
                  onRepeatPlus: () => onRepsChanged(10),
                  onValueTap: onRepsSet == null ? null : () => _typeReps(context),
                  valueKey: const ValueKey<String>('reps-value'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: NumberStepper(
                  value: isZeroKg(kg) ? 'BW' : kg,
                  unit: isZeroKg(kg) ? 'body' : 'kg',
                  onMinus: () => onKgChanged(-2.5),
                  onPlus: () => onKgChanged(2.5),
                  onRepeatMinus: () => onKgChanged(-10),
                  onRepeatPlus: () => onKgChanged(10),
                  onValueTap: onKgSet == null ? null : () => _typeKg(context),
                  valueKey: const ValueKey<String>('kg-value'),
                ),
              ),
            ],
          ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _FailedPill(value: failed, onChanged: onFailedChanged),
          ),
        ],
      ),
    );
  }
}

/// A quiet toggle under the steppers: a small box and the words. Ink when on.
class _FailedPill extends StatelessWidget {
  const _FailedPill({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final Color fg = value ? OG.ink : OG.mute;
    return GestureDetector(
      key: const ValueKey<String>('last-rep-failed'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onChanged(!value);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 6, 12, 0),
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
                style: OG.body(size: 14, weight: value ? FontWeight.w700 : FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// A value with a minus and a plus button. A long press on a button calls
/// the optional [onLongMinus] or [onLongPlus] once (a larger step). Or, with
/// [onRepeatMinus] or [onRepeatPlus], it calls that at once and then again
/// every [stepperRepeatInterval] until release, or until the value stops
/// changing (a limit was reached).
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.value,
    required this.unit,
    required this.onMinus,
    required this.onPlus,
    this.onLongMinus,
    this.onLongPlus,
    this.onRepeatMinus,
    this.onRepeatPlus,
    this.onValueTap,
    this.valueKey,
  });

  /// Key of the tappable value (default `stepper-value`).
  final Key? valueKey;

  /// Tap on the value itself (for example to type one). Null: the value is not a control.
  final VoidCallback? onValueTap;

  final String value;
  final String unit;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback? onLongMinus;
  final VoidCallback? onLongPlus;
  final VoidCallback? onRepeatMinus;
  final VoidCallback? onRepeatPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        StepperButton(
          icon: Icons.remove,
          onTap: onMinus,
          onLongPress: onLongMinus,
          onRepeat: onRepeatMinus,
          value: value,
        ),
        Expanded(
          child: GestureDetector(
            key: onValueTap == null ? null : (valueKey ?? const ValueKey<String>('stepper-value')),
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
        StepperButton(
          icon: Icons.add,
          onTap: onPlus,
          onLongPress: onLongPlus,
          onRepeat: onRepeatPlus,
          value: value,
        ),
      ],
    );
  }
}

/// Time between repeats while a stepper button is held. The first repeat
/// fires when the long press is recognised (about 500 ms after touch).
const Duration stepperRepeatInterval = Duration(milliseconds: 400);

class StepperButton extends StatefulWidget {
  const StepperButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.onRepeat,
    this.value,
  });

  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Called at once on long press, then every [stepperRepeatInterval] until
  /// release. Wins over [onLongPress].
  final VoidCallback? onRepeat;

  /// The shown value. While repeating, an unchanged value between two repeats
  /// means a limit was reached, and the repeat stops. Null: never stops this way.
  final String? value;

  @override
  State<StepperButton> createState() => _StepperButtonState();
}

class _StepperButtonState extends State<StepperButton> {
  Timer? _timer;
  String? _valueAtLastFire;

  void _fire() {
    HapticFeedback.lightImpact();
    _valueAtLastFire = widget.value;
    widget.onRepeat!();
  }

  void _start() {
    _stop();
    _fire();
    _timer = Timer.periodic(stepperRepeatInterval, (Timer _) {
      if (widget.value != null && widget.value == _valueAtLastFire) {
        _stop();
        return;
      }
      _fire();
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VoidCallback? once = widget.onLongPress;
    final bool repeat = widget.onRepeat != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onLongPress: repeat || once == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              once();
            },
      onLongPressStart: repeat ? (LongPressStartDetails _) => _start() : null,
      onLongPressEnd: repeat ? (LongPressEndDetails _) => _stop() : null,
      onLongPressCancel: repeat ? _stop : null,
      child: Container(
        width: 42,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: OG.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OG.ink, width: 2),
        ),
        child: Icon(widget.icon, size: 22, color: OG.ink),
      ),
    );
  }
}
