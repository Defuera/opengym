import 'package:flutter/material.dart';

import '../models.dart';
import '../stores/about_store.dart';
import '../theme.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/feeling_card.dart';
import '../widgets/footnote.dart';
import '../widgets/note_box.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/record_card.dart';
import '../widgets/rule_row.dart';
import '../widgets/section_header.dart';
import '../widgets/segmented_toggle.dart';
import '../widgets/sheet_link.dart';
import 'limit_sheets.dart';
import 'record_sheets.dart';

/// One limit: status, rules for the coach, how it felt, and the user's records.
class LimitDetailScreen extends StatelessWidget {
  const LimitDetailScreen({
    super.key,
    required this.about,
    required this.limitId,
    required this.exercises,
    this.onAskCoach,
  });

  /// Opens the chat to change this limit (ADR-032, step D). Null: no link.
  final VoidCallback? onAskCoach;

  final AboutStore about;
  final String limitId;

  /// Known exercise names, for the rule sheet.
  final List<String> exercises;

  Future<void> _editRule(BuildContext context, Limit l, {int? index}) async {
    final RuleEdit? r = await showRuleSheet(
      context,
      exercises: exercises,
      initial: index == null ? null : l.rules[index],
    );
    if (r == null || !context.mounted) {
      return;
    }
    final List<LimitRule> rules = List<LimitRule>.from(l.rules);
    if (r.remove) {
      final bool ok = await confirmDelete(context, title: 'Delete this rule?', label: 'Delete rule');
      if (!ok || !context.mounted) {
        return;
      }
      rules.removeAt(index!);
    } else if (index == null) {
      if (rules.length >= 12) {
        return;
      }
      rules.add(r.rule!);
    } else {
      rules[index] = r.rule!;
    }
    await about.setRules(l, rules);
  }

  Future<void> _addRecord(BuildContext context, Limit l) async {
    final RecordDraft? d = await showRecordSheet(context);
    if (d != null) {
      await about.addRecord(limitId: l.id, title: d.title, text: d.text, date: d.date);
    }
  }

  Future<void> _openRecord(BuildContext context, LimitRecord r) async {
    final String? res = await showRecordView(context, r);
    if (res == 'remove') {
      if (!context.mounted) {
        return;
      }
      final bool ok = await confirmDelete(context, title: 'Delete this record?', label: 'Delete record');
      if (!ok) {
        return;
      }
      await about.removeRecord(r.id);
    }
  }

  Future<void> _delete(BuildContext context, Limit l) async {
    final bool ok = await confirmDelete(
      context,
      title: 'Delete this limit?',
      label: 'Delete limit, rules and records',
    );
    if (ok) {
      await about.removeLimit(l.id);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  String _history(Checkin c) {
    final String label = c.sessionLabel == null ? '' : ' · ${c.sessionLabel}';
    return '${shortDate(c.at)}$label';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: about,
      builder: (BuildContext context, Widget? child) {
        final Limit? l = about.limit(limitId);
        return Scaffold(
          body: SafeArea(
            child: l == null
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        OgIconButton(icon: Icons.chevron_left, onPressed: () => Navigator.of(context).pop()),
                        const SizedBox(height: 18),
                        const NoteBox(title: 'This limit is gone.', message: 'Go back to About me.'),
                      ],
                    ),
                  )
                : _body(context, l),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, Limit l) {
    final String since = l.since == null ? '' : ' · since ${sinceLabel(l.since!)}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Limit$since', style: OG.muted(size: 14, weight: FontWeight.w600)),
                  Text(l.title, style: OG.display(32)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OgIconButton(icon: Icons.chevron_left, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
        const SectionHeader(title: 'Status'),
        const SizedBox(height: 6),
        SegmentedToggle(
          labels: <String>[for (final String s in limitStatuses) statusLabel(s)],
          selectedIndex: limitStatuses.indexOf(l.status).clamp(0, 2),
          onChanged: (int i) => about.setStatus(l, limitStatuses[i]),
        ),
        if (onAskCoach != null)
          KeyedSubtree(
            key: const ValueKey<String>('limit-ask-coach'),
            child: SheetLink(label: 'Change with the coach', onTap: onAskCoach!),
          ),
        SectionHeader(title: 'Rules for the coach', action: '+ Add', onAction: () => _editRule(context, l)),
        if (l.rules.isEmpty)
          const NoteBox(title: 'No rules yet.', message: 'Add what to avoid, keep light or do.')
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: ogBox(),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < l.rules.length; i++)
                  RuleRow(
                    kind: l.rules[i].kind,
                    label: ruleKindLabel(l.rules[i].kind),
                    text: l.rules[i].text,
                    onTap: () => _editRule(context, l, index: i),
                  ),
              ],
            ),
          ),
        const Footnote('A plan that breaks an "Avoid" rule is rejected before you see it.'),
        const SectionHeader(title: 'How it felt'),
        const SizedBox(height: 6),
        FeelingCard(
          question: 'How was the ${partNoun(l.part)} today?',
          onAnswer: (String f) => about.checkin(l.id, f),
        ),
        if (l.checkins.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: ogBox(),
            child: Column(
              children: <Widget>[
                for (final Checkin c in l.checkins)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(_history(c), style: OG.body(size: 14, weight: FontWeight.w700)),
                        ),
                        Text(feelingLabel(c.feeling), style: OG.muted(size: 14)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        SectionHeader(title: 'My records', action: '+ Add', onAction: () => _addRecord(context, l)),
        for (final LimitRecord r in l.records) ...<Widget>[
          RecordCard(
            title: r.date == null ? r.title : '${r.title} · ${longDate(r.date!)}',
            preview: r.text,
            onTap: () => _openRecord(context, r),
          ),
          const SizedBox(height: 10),
        ],
        const Footnote(
          'Records are yours. The app stores them word for word. It does not read them, '
          'and the coach never receives them.',
        ),
        const SizedBox(height: 24),
        OgButton(onPressed: () => _delete(context, l), child: const Text('Delete limit')),
      ],
    );
  }
}
