import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'choice_sheet.dart';
import 'og_button.dart';
import 'set_check.dart';
import 'set_editor_card.dart';
import 'set_row.dart';
import 'text_sheet.dart';
import 'time_format.dart';

/// Plain data for one entry of a time exercise, so widgets need no model imports.
class TimeRowData {
  const TimeRowData({
    required this.id,
    required this.minutes,
    this.distanceKm,
    this.done = false,
  });

  /// Stable identity, used as the swipe key.
  final Object id;
  final double minutes;

  /// The distance as shown ("10.9"), or null when none is set.
  final String? distanceKm;
  final bool done;
}

/// A countdown time as "m:ss", rounded up to the full second: 90 s is "1:30".
String countdownLabel(Duration d) {
  final int total = (d.inMilliseconds / 1000).ceil().clamp(0, 1 << 30);
  final int s = total % 60;
  return '${total ~/ 60}:${s < 10 ? '0' : ''}$s';
}

/// "30 s", "25 min" or "1:30 min", then ", 10.9 km" when there is a distance.
String timeLabel(double minutes, String? km) => '${formatTimeEntry(minutes)}${km == null ? '' : ', $km km'}';

/// The entries of a time exercise (usually one). Only the [selected] one is an
/// editor: a minutes stepper and an optional distance field. Swipe a row left
/// to remove it (not allowed for the last remaining one).
class TimeList extends StatelessWidget {
  const TimeList({
    super.key,
    required this.entries,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    required this.onRemove,
    required this.onMinutesChanged,
    required this.onDistanceChanged,
    this.onMinutesSet,
    this.onToggle,
    this.checkPrefix = 'set-check',
    this.countdownIndex,
    this.remaining = Duration.zero,
    this.paused = false,
    this.onStart,
    this.onPauseResume,
    this.onReset,
  });

  final List<TimeRowData> entries;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<double> onMinutesChanged;
  final ValueChanged<double?> onDistanceChanged;

  /// The person typed a time for the selected entry (in minutes). Null: the time cannot be typed.
  final ValueChanged<double>? onMinutesSet;

  /// Tap on an entry's check control (complete or undo). Null: no check controls.
  final ValueChanged<int>? onToggle;

  /// Check keys are `'<checkPrefix>-<index>'`.
  final String checkPrefix;

  /// The entry that has the active countdown, or null. Its row shows
  /// [remaining]; when it is the selected one its card shows the countdown.
  final int? countdownIndex;
  final Duration remaining;
  final bool paused;

  /// Starts a countdown for the selected entry. Null: no Start button.
  final VoidCallback? onStart;
  final VoidCallback? onPauseResume;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[];
    for (int i = 0; i < entries.length; i++) {
      final TimeRowData x = entries[i];
      if (i == selected) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TimeEditorCard(
            key: ValueKey<Object>(x.id),
            number: i + 1,
            title: entries.length > 1 ? 'Round ${i + 1}' : 'Time',
            minutes: x.minutes,
            distance: x.distanceKm,
            done: x.done,
            onCheck: onToggle == null ? null : () => onToggle!(i),
            checkKey: ValueKey<String>('$checkPrefix-$i'),
            onMinutesChanged: onMinutesChanged,
            onMinutesSet: onMinutesSet,
            onDistanceChanged: onDistanceChanged,
            countdown: countdownIndex == i ? remaining : null,
            paused: paused,
            onStart: x.done ? null : onStart,
            onPauseResume: onPauseResume,
            onReset: onReset,
          ),
        ));
        continue;
      }
      items.add(Dismissible(
        key: ObjectKey(x.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (DismissDirection d) async {
          if (entries.length <= 1) {
            return false;
          }
          return confirmDelete(context, title: 'Delete this entry?', label: 'Delete entry');
        },
        onDismissed: (DismissDirection d) => onRemove(i),
        background: Container(
          color: OG.soft,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          child: Text('Remove', style: OG.body(size: 14, weight: FontWeight.w700, color: OG.mute)),
        ),
        child: _TimeRow(
          number: i + 1,
          data: x,
          remaining: countdownIndex == i ? remaining : null,
          onTap: () => onSelect(i),
          onCheck: onToggle == null ? null : () => onToggle!(i),
          checkKey: ValueKey<String>('$checkPrefix-$i'),
        ),
      ));
    }
    items.add(_AddRow(onTap: onAdd));
    return Column(children: items);
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.number,
    required this.data,
    required this.onTap,
    this.remaining,
    this.onCheck,
    this.checkKey,
  });

  final int number;
  final TimeRowData data;

  /// Time left of this row's countdown; shows in place of the minutes.
  final Duration? remaining;
  final VoidCallback onTap;
  final VoidCallback? onCheck;
  final Key? checkKey;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: const BoxDecoration(
          color: OG.card,
          border: Border(bottom: BorderSide(color: OG.soft, width: 1.5)),
        ),
        child: Row(
          children: <Widget>[
            SetBadge(number: number, done: data.done),
            const SizedBox(width: 14),
            Text(
              remaining != null ? countdownLabel(remaining!) : timeLabel(data.minutes, data.distanceKm),
              key: remaining != null ? const ValueKey<String>('countdown-row-time') : null,
              style: OG.display(20, color: data.done ? OG.mute : OG.ink),
            ),
            const Spacer(),
            if (onCheck != null) SetCheck(key: checkKey, done: data.done, onTap: onCheck!),
          ],
        ),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 46,
        child: Row(
          children: <Widget>[
            const SetBadge(dashed: true),
            const SizedBox(width: 14),
            Text('Add round', style: OG.body(size: 15, weight: FontWeight.w700, color: OG.mute)),
          ],
        ),
      ),
    );
  }
}

/// The current entry of a time exercise, expanded: badge and title, a minutes
/// stepper (step 1, long press steps 5) and a distance in km that shows only
/// when set or after a tap on "Add distance".
class TimeEditorCard extends StatefulWidget {
  const TimeEditorCard({
    super.key,
    required this.number,
    required this.title,
    required this.minutes,
    required this.onMinutesChanged,
    required this.onDistanceChanged,
    this.onMinutesSet,
    this.distance,
    this.done = false,
    this.onCheck,
    this.checkKey,
    this.countdown,
    this.paused = false,
    this.onStart,
    this.onPauseResume,
    this.onReset,
  });

  final int number;
  final String title;
  final double minutes;
  final String? distance;
  final ValueChanged<double> onMinutesChanged;
  final ValueChanged<double?> onDistanceChanged;

  /// A tap on the time opens a field to type it ("2:30"); this gets the minutes.
  /// Null: the time is changed with the steps only.
  final ValueChanged<double>? onMinutesSet;
  final bool done;

  /// Tap on the check control; null hides the control.
  final VoidCallback? onCheck;
  final Key? checkKey;

  /// Time left when a countdown is active for this entry; null otherwise.
  /// While set, the steppers are hidden.
  final Duration? countdown;
  final bool paused;

  /// "Start" shows when this is set (and no countdown is active).
  final VoidCallback? onStart;
  final VoidCallback? onPauseResume;
  final VoidCallback? onReset;

  @override
  State<TimeEditorCard> createState() => _TimeEditorCardState();
}

class _TimeEditorCardState extends State<TimeEditorCard> {
  late final TextEditingController _km = TextEditingController(text: widget.distance ?? '');

  /// The distance field shows when the entry has a distance, or after "Add distance".
  late bool _showKm = widget.distance != null;

  @override
  void dispose() {
    _km.dispose();
    super.dispose();
  }

  /// Asks for a typed time and passes it on. A text that is not a time changes nothing.
  Future<void> _typeTime() async {
    final String? text = await showTextSheet(
      context,
      title: 'Time',
      label: 'Minutes and seconds',
      hint: '2:30, 10 or 45s',
      actionLabel: 'Set',
      initialText: timeEntryText(widget.minutes),
    );
    final double? minutes = text == null ? null : parseTimeEntry(text);
    if (minutes != null) {
      widget.onMinutesSet?.call(minutes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final OutlineInputBorder idle = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: OG.ink, width: 2),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
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
              SetBadge(number: widget.number, accent: true),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OG.body(size: 15, weight: FontWeight.w800),
                ),
              ),
              if (widget.onCheck != null)
                Transform.translate(
                  offset: const Offset(6, 0),
                  child: SetCheck(key: widget.checkKey, done: widget.done, onTap: widget.onCheck!),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (widget.countdown != null)
            ..._countdown(widget.countdown!)
          else ...<Widget>[
            NumberStepper(
              value: timeValue(widget.minutes),
              unit: timeUnit(widget.minutes).toLowerCase(),
              onMinus: () => widget.onMinutesChanged(-1),
              onPlus: () => widget.onMinutesChanged(1),
              onLongMinus: () => widget.onMinutesChanged(-5),
              onLongPlus: () => widget.onMinutesChanged(5),
              onValueTap: widget.onMinutesSet == null ? null : _typeTime,
            ),
            const SizedBox(height: 12),
            if (widget.distance == null && isShortTime(widget.minutes))
              const SizedBox.shrink()
            else if (!_showKm)
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  key: const ValueKey<String>('time-add-distance'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _showKm = true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('Add distance', style: OG.muted(size: 14, weight: FontWeight.w600)),
                  ),
                ),
              )
            else
            TextField(
              key: const ValueKey<String>('time-distance'),
              controller: _km,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(7),
              ],
              style: OG.body(),
              onChanged: (String t) => widget.onDistanceChanged(double.tryParse(t.replaceAll(',', '.'))),
              decoration: InputDecoration(
                hintText: 'Distance in km (optional)',
                filled: true,
                fillColor: OG.card,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: idle,
                enabledBorder: idle,
                focusedBorder: idle.copyWith(borderSide: const BorderSide(color: OG.accent, width: 3)),
              ),
            ),
            if (widget.onStart != null) ...<Widget>[
              const SizedBox(height: 12),
              OgButton(
                key: const ValueKey<String>('countdown-start'),
                variant: OgVariant.accent,
                minHeight: 48,
                onPressed: widget.onStart,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.play_arrow_rounded, color: OG.white, size: 26),
                    const SizedBox(width: 6),
                    Text('Start', style: OG.display(18, color: OG.white)),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> _countdown(Duration left) {
    return <Widget>[
      const SizedBox(height: 4),
      Text(
        countdownLabel(left),
        key: const ValueKey<String>('countdown-time'),
        style: OG.display(56, color: widget.paused ? OG.mute : OG.ink),
      ),
      const SizedBox(height: 8),
      OgButton(
        key: const ValueKey<String>('countdown-toggle'),
        variant: OgVariant.accent,
        minHeight: 48,
        onPressed: widget.onPauseResume,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(widget.paused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: OG.white, size: 26),
            const SizedBox(width: 6),
            Text(widget.paused ? 'Resume' : 'Pause', style: OG.display(18, color: OG.white)),
          ],
        ),
      ),
      GestureDetector(
        key: const ValueKey<String>('countdown-reset'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onReset,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text('Reset', style: OG.muted(size: 14, weight: FontWeight.w600)),
        ),
      ),
    ];
  }
}
