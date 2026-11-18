import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/labeled_field.dart';
import '../widgets/og_button.dart';
import '../widgets/og_chip.dart';
import '../widgets/og_sheet.dart';
import '../widgets/segmented_toggle.dart';

/// What the add-limit sheet returns.
class LimitDraft {
  const LimitDraft({required this.part, required this.title, required this.status});

  final String part;
  final String title;
  final String status;
}

/// Add a limit: pick the part, name it, set its status. [initialPart] comes
/// from a tap on the figure.
Future<LimitDraft?> showAddLimitSheet(BuildContext context, {String? initialPart}) {
  return showOgSheet<LimitDraft>(
    context,
    (BuildContext c) => _AddLimit(initialPart: initialPart),
    title: 'Add a limit',
  );
}

class _AddLimit extends StatefulWidget {
  const _AddLimit({this.initialPart});

  final String? initialPart;

  @override
  State<_AddLimit> createState() => _AddLimitState();
}

class _AddLimitState extends State<_AddLimit> {
  late String? _part = widget.initialPart;
  late final TextEditingController _title =
      TextEditingController(text: _part == null ? '' : partLabel(_part!));
  bool _edited = false;
  int _status = 0;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _pick(String key) {
    setState(() {
      _part = key;
      if (!_edited) {
        _title.text = partLabel(key);
      }
    });
  }

  void _save() {
    final String t = _title.text.trim();
    if (_part == null || t.isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      LimitDraft(part: _part!, title: t, status: _status == 0 ? 'active' : 'improving'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Body part', style: OG.muted(size: 14, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String k in limitPartKeys)
              OgChip(label: partLabel(k), selected: _part == k, onTap: () => _pick(k)),
          ],
        ),
        const SizedBox(height: 14),
        LabeledField(
          label: 'Title',
          controller: _title,
          hint: 'Left knee',
          onChanged: (String v) => _edited = true,
        ),
        const SizedBox(height: 14),
        SegmentedToggle(
          labels: const <String>['Active', 'Improving'],
          selectedIndex: _status,
          onChanged: (int i) => setState(() => _status = i),
        ),
        const SizedBox(height: 14),
        OgButton(
          variant: OgVariant.accent,
          onPressed: _part == null ? null : _save,
          child: const Text('Add limit'),
        ),
      ],
    );
  }
}

/// What the rule sheet returns: a rule to keep, or [remove].
class RuleEdit {
  const RuleEdit.save(LimitRule this.rule) : remove = false;
  const RuleEdit.delete()
      : rule = null,
        remove = true;

  final LimitRule? rule;
  final bool remove;
}

/// Add or change one rule. With [initial] the sheet also offers Remove.
/// [exercises] are the known exercise names to pick from.
Future<RuleEdit?> showRuleSheet(
  BuildContext context, {
  required List<String> exercises,
  LimitRule? initial,
}) {
  return showOgSheet<RuleEdit>(
    context,
    (BuildContext c) => _RuleForm(exercises: exercises, initial: initial),
    title: initial != null ? 'Change rule' : 'Add a rule',
  );
}

class _RuleForm extends StatefulWidget {
  const _RuleForm({required this.exercises, this.initial});

  final List<String> exercises;
  final LimitRule? initial;

  @override
  State<_RuleForm> createState() => _RuleFormState();
}

class _RuleFormState extends State<_RuleForm> {
  late int _kind = widget.initial == null ? 0 : ruleKinds.indexOf(widget.initial!.kind).clamp(0, 2);
  late final TextEditingController _text = TextEditingController(text: widget.initial?.text ?? '');
  late final Set<String> _picked = <String>{...?widget.initial?.exercises};

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final String t = _text.text.trim();
    if (t.isEmpty) {
      return;
    }
    Navigator.of(context).pop(RuleEdit.save(LimitRule(
      kind: ruleKinds[_kind],
      text: t.length > 120 ? t.substring(0, 120) : t,
      exercises: <String>[
        for (final String e in widget.exercises)
          if (_picked.contains(e)) e,
      ].take(20).toList(),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.initial != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SegmentedToggle(
          labels: <String>[for (final String k in ruleKinds) ruleKindLabel(k)],
          selectedIndex: _kind,
          onChanged: (int i) => setState(() => _kind = i),
        ),
        const SizedBox(height: 14),
        LabeledField(
          label: 'Rule, in training words',
          controller: _text,
          hint: 'Leg extension machine',
          maxLines: 2,
        ),
        const SizedBox(height: 14),
        Text('Exercises (optional)', style: OG.muted(size: 14, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String e in widget.exercises)
              OgChip(
                label: e,
                selected: _picked.contains(e),
                onTap: () =>
                    setState(() => _picked.contains(e) ? _picked.remove(e) : _picked.add(e)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        OgButton(
            variant: OgVariant.accent,
            onPressed: _save,
            child: Text(editing ? 'Save rule' : 'Add rule')),
        if (editing) ...<Widget>[
          const SizedBox(height: 8),
          OgButton(
            onPressed: () => Navigator.of(context).pop(const RuleEdit.delete()),
            child: const Text('Remove rule'),
          ),
        ],
      ],
    );
  }
}
