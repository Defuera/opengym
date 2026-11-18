import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../entry_text.dart';
import '../models.dart';
import '../planner.dart';
import '../session_text.dart';
import '../theme.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/cta_button.dart';
import '../widgets/exercise_picker.dart';
import '../widgets/labeled_field.dart';
import '../widgets/note_box.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import 'session_edit_parts.dart';

/// Corrects a finished session: same id, saved through the store, so the
/// outbox sends it like a new one. `source`, `importId` and `kind` never
/// change. It is not a live session: no timers, no rest clock, no "active
/// session". Save writes; leaving with changes asks first.
class SessionEditScreen extends StatefulWidget {
  const SessionEditScreen({super.key, required this.deps, required this.session});

  final AppDeps deps;
  final Session session;

  @override
  State<SessionEditScreen> createState() => _SessionEditScreenState();
}

class _SessionEditScreenState extends State<SessionEditScreen> {
  late final Session _orig = widget.session;
  late final String _origJson = jsonEncode(_orig.toJson());

  /// The working copy. The stored session is replaced only on Save.
  late final Session _work = Session.fromJson(jsonDecode(_origJson) as Map<String, dynamic>);

  late DateTime _start = DateTime.fromMillisecondsSinceEpoch(_orig.startedAt);
  late final int _span = (_orig.endedAt ?? _orig.startedAt) - _orig.startedAt;
  late final TextEditingController _focus = TextEditingController(text: _orig.focus ?? '');
  late final TextEditingController _note = TextEditingController(text: _orig.note ?? '');
  late final TextEditingController _minutes = TextEditingController(text: '${_origMinutes()}');
  late final TextEditingController _km =
      TextEditingController(text: _orig.distanceKm == null ? '' : fmtKg(_orig.distanceKm!));
  final Map<Exercise, int> _sel = <Exercise, int>{};

  bool get _gym => _orig.kind == 'gym';
  bool get _timed => hasRealTimes(_orig);

  int _origMinutes() => _gym ? sessionMinutes(_orig) : (_orig.minutes ?? sessionMinutes(_orig));

  @override
  void dispose() {
    _focus.dispose();
    _note.dispose();
    _minutes.dispose();
    _km.dispose();
    super.dispose();
  }

  int? get _min {
    final int? m = int.tryParse(_minutes.text.trim());
    return (m == null || m < 1 || m > 1000) ? null : m;
  }

  /// The session as the form holds it now.
  Session _current() {
    final String f = _focus.text.trim();
    final String n = _note.text.trim();
    final int? m = _min;
    int span = _span;
    if (_gym && _timed) {
      if (m != null && m != _origMinutes()) {
        span = m * 60000;
      }
    } else if (!_gym && m != null) {
      span = _span + (m - _origMinutes()) * 60000;
    }
    final int start = _start.millisecondsSinceEpoch;
    final double? km = double.tryParse(_km.text.trim().replaceAll(',', '.'));
    return Session(
      id: _orig.id,
      kind: _orig.kind,
      type: _orig.type,
      focus: _gym ? (f.isEmpty ? null : f) : _orig.focus,
      startedAt: start,
      endedAt: start + (span < 0 ? 0 : span),
      exercises: _work.exercises,
      minutes: _gym ? _orig.minutes : (m ?? _orig.minutes),
      distanceKm: _gym ? _orig.distanceKm : ((km == null || km <= 0) ? null : km),
      note: n.isEmpty ? null : n,
      source: _orig.source,
      importId: _orig.importId,
      planNote: _orig.planNote,
    );
  }

  bool get _dirty => jsonEncode(_current().toJson()) != _origJson;

  bool get _valid {
    if (_gym) {
      return _work.exercises.isNotEmpty && (!_timed || _min != null);
    }
    return _min != null;
  }

  void _save() {
    final Session s = _current();
    // Every set of a saved session is a done one.
    for (final Exercise e in s.exercises) {
      for (final SetEntry x in e.sets) {
        x.done = true;
      }
    }
    widget.deps.store.updateSession(s);
    Navigator.of(context).pop(true);
  }

  Future<void> _askLeave() async {
    final String? c = await showChoiceSheet(
      context,
      title: 'Leave without saving?',
      choices: const <SheetChoice>[
        SheetChoice(value: 'leave', label: 'Leave without saving'),
        SheetChoice(value: 'stay', label: 'Keep editing', variant: OgVariant.dashed),
      ],
    );
    if (c == 'leave' && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _addExercise() async {
    final ExerciseChoice? pick = await showExercisePicker(
      context,
      title: 'Add exercise',
      options: <ExerciseOption>[
        for (final LoggedExercise x in loggedExercises(widget.deps.store.sessions))
          ExerciseOption(x.name, timed: x.measure == measureTime),
      ],
    );
    if (pick == null || pick.name.isEmpty) {
      return;
    }
    final Exercise e = makeExercise(
      widget.deps.store.sessions,
      pick.name,
      measure: pick.timed ? measureTime : measureSets,
    );
    setState(() => _work.exercises.add(e));
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _start.isAfter(now) ? now : _start,
      firstDate: DateTime(2000),
      lastDate: now.isAfter(_start) ? now : _start,
    );
    if (d != null) {
      setState(() => _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute));
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? t =
        await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t != null) {
      setState(() => _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final int ms = _start.millisecondsSinceEpoch;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _askLeave();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        OgIconButton(
                          icon: Icons.chevron_left,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Edit ${_orig.type.toLowerCase()}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: OG.display(32)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OgButton(
                            key: const ValueKey<String>('edit-date'),
                            onPressed: _pickDate,
                            child: Text(dateText(ms)),
                          ),
                        ),
                        if (_gym || _timed) ...<Widget>[
                          const SizedBox(width: 12),
                          Expanded(
                            child: OgButton(
                              key: const ValueKey<String>('edit-time'),
                              onPressed: _pickTime,
                              child: Text(clockText(ms)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_gym && _timed || !_gym) ...<Widget>[
                      const SizedBox(height: 18),
                      LabeledField(
                        label: 'Minutes',
                        controller: _minutes,
                        keyboardType: TextInputType.number,
                        onChanged: (String _) => setState(() {}),
                        key: const ValueKey<String>('edit-minutes'),
                      ),
                    ],
                    if (!_gym) ...<Widget>[
                      const SizedBox(height: 18),
                      LabeledField(
                        label: 'Distance in km (optional)',
                        controller: _km,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (String _) => setState(() {}),
                        key: const ValueKey<String>('edit-km'),
                      ),
                    ],
                    if (_gym) ...<Widget>[
                      const SizedBox(height: 18),
                      LabeledField(
                        label: 'Focus (optional)',
                        controller: _focus,
                        hint: 'For example Upper or Legs',
                        maxLength: 40,
                        onChanged: (String _) => setState(() {}),
                        key: const ValueKey<String>('edit-focus'),
                      ),
                      const SizedBox(height: 18),
                      for (final Exercise e in _work.exercises) ...<Widget>[
                        ExerciseEditor(
                          key: ObjectKey(e),
                          exercise: e,
                          selected: _sel[e] ?? 0,
                          onSelect: (int i) => setState(() => _sel[e] = i),
                          onChanged: () => setState(() {}),
                          onRemove: () => setState(() => _work.exercises.remove(e)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_work.exercises.isEmpty) ...<Widget>[
                        const NoteBox(
                          title: 'No exercises.',
                          message: 'Add at least one to save.',
                        ),
                        const SizedBox(height: 12),
                      ],
                      OgButton(
                        key: const ValueKey<String>('edit-add-exercise'),
                        variant: OgVariant.dashed,
                        onPressed: _addExercise,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.add, size: 22),
                            SizedBox(width: 8),
                            Text('Add exercise'),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    LabeledField(
                      label: 'Note (optional)',
                      controller: _note,
                      minLines: 2,
                      maxLines: 6,
                      autocorrect: true,
                      keyboardType: TextInputType.multiline,
                      onChanged: (String _) => setState(() {}),
                      key: const ValueKey<String>('edit-note'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: CtaButton(
                  label: 'Save',
                  icon: Icons.check,
                  variant: OgVariant.accent,
                  onPressed: (_dirty && _valid) ? _save : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
