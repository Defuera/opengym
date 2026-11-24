import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/labeled_field.dart';
import '../widgets/og_button.dart';
import '../widgets/og_chip.dart';
import '../widgets/og_sheet.dart';
import '../widgets/segmented_toggle.dart';

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
