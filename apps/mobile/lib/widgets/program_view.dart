import 'package:flutter/material.dart';

import '../theme.dart';
import 'section_header.dart';

/// One session of a phase, as text lines.
class ProgramSessionView {
  const ProgramSessionView({required this.title, required this.lines, this.note});

  final String title;

  /// One line per exercise, for example "Leg press · 3 × 12 × 40 kg".
  final List<String> lines;
  final String? note;
}

/// One phase: a title, its weeks as words, a note and its sessions.
class ProgramPhaseView {
  const ProgramPhaseView({
    required this.title,
    required this.weeks,
    this.note = '',
    required this.sessions,
    this.current = false,
    this.open = false,
  });

  final String title;

  /// For example "Weeks 1 to 2".
  final String weeks;
  final String note;
  final List<ProgramSessionView> sessions;

  /// The phase the program is in now: marked and open.
  final bool current;

  /// Starts open (a current phase always does).
  final bool open;
}

/// One session slot of this week, with a tick when done.
class ProgramSlotView {
  const ProgramSlotView({required this.label, required this.done});

  final String label;
  final bool done;
}

/// One test of the program.
class ProgramTestView {
  const ProgramTestView({required this.text, this.done = false});

  final String text;
  final bool done;
}

/// A program as plain values, compact: title, purpose, dates, the week as
/// chips, the phases as collapsible cards, the rules and the tests. It is used
/// for a proposal and for an active program (then with [slots] and a phase
/// marked as current).
class ProgramView extends StatelessWidget {
  const ProgramView({
    super.key,
    required this.title,
    this.purpose = '',
    this.dates = '',
    this.week = const <String>[],
    this.slots,
    required this.phases,
    this.rules = const <String>[],
    this.tests = const <ProgramTestView>[],
  });

  final String title;
  final String purpose;

  /// For example "19 Nov to 15 Dec · 4 weeks".
  final String dates;

  /// The pattern of one week: a label per slot, in order.
  final List<String> week;

  /// This week's slots. When given, they show in place of [week], with ticks.
  final List<ProgramSlotView>? slots;
  final List<ProgramPhaseView> phases;
  final List<String> rules;
  final List<ProgramTestView> tests;

  @override
  Widget build(BuildContext context) {
    final List<ProgramSlotView>? s = slots;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title, style: OG.display(28)),
        if (purpose.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(purpose, style: OG.muted(size: 15)),
        ],
        if (dates.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(dates, style: OG.body(size: 14, weight: FontWeight.w700)),
        ],
        if (s != null && s.isNotEmpty) ...<Widget>[
          const SectionHeader(title: 'This week'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (int i = 0; i < s.length; i++) _Chip(key: ValueKey<String>('slot-$i'), label: s[i].label, done: s[i].done),
            ],
          ),
        ] else if (week.isNotEmpty) ...<Widget>[
          const SectionHeader(title: 'A week'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[for (final String k in week) _Chip(label: k)],
          ),
        ],
        const SectionHeader(title: 'Phases'),
        for (int i = 0; i < phases.length; i++) ...<Widget>[
          _PhaseCard(index: i, phase: phases[i]),
          const SizedBox(height: 10),
        ],
        if (rules.isNotEmpty) ...<Widget>[
          const SectionHeader(title: 'Rules'),
          for (final String r in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('•  ', style: OG.body(size: 15)),
                  Expanded(child: Text(r, style: OG.body(size: 15))),
                ],
              ),
            ),
        ],
        if (tests.isNotEmpty) ...<Widget>[
          const SectionHeader(title: 'Tests'),
          for (final ProgramTestView t in tests)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(t.done ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: t.done ? OG.accent : OG.mute),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.text, style: OG.body(size: 15))),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, this.done});

  /// [done] null: a plain label; otherwise a slot with a tick or an empty circle.
  final String label;
  final bool? done;

  @override
  Widget build(BuildContext context) {
    final bool tick = done ?? false;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tick ? OG.done : OG.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: OG.ink, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (done != null) ...<Widget>[
            Icon(tick ? Icons.check : Icons.circle_outlined, size: 16, color: OG.ink),
            const SizedBox(width: 6),
          ],
          Text(label, style: OG.body(size: 14, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PhaseCard extends StatefulWidget {
  const _PhaseCard({required this.index, required this.phase});

  final int index;
  final ProgramPhaseView phase;

  @override
  State<_PhaseCard> createState() => _PhaseCardState();
}

class _PhaseCardState extends State<_PhaseCard> {
  late bool _open = widget.phase.current || widget.phase.open;

  @override
  Widget build(BuildContext context) {
    final ProgramPhaseView p = widget.phase;
    return Container(
      decoration: ogBox(color: p.current ? OG.done : OG.card, offset: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GestureDetector(
            key: ValueKey<String>('phase-${widget.index}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(p.title, style: OG.body(size: 17, weight: FontWeight.w800)),
                        Text(p.weeks, style: OG.muted(size: 14)),
                      ],
                    ),
                  ),
                  if (p.current)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: OG.ink, borderRadius: BorderRadius.circular(20)),
                      child: Text('Now', style: OG.body(size: 13, weight: FontWeight.w800, color: OG.white)),
                    ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 26, color: OG.ink),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (p.note.isNotEmpty) ...<Widget>[
                    Text(p.note, style: OG.muted(size: 14)),
                    const SizedBox(height: 8),
                  ],
                  for (final ProgramSessionView s in p.sessions) ...<Widget>[
                    const Divider(height: 1, thickness: 1.5, color: OG.soft),
                    const SizedBox(height: 8),
                    Text(s.title, style: OG.body(size: 16, weight: FontWeight.w800)),
                    for (final String l in s.lines) Text(l, style: OG.muted(size: 14)),
                    if ((s.note ?? '').isNotEmpty) Text(s.note!, style: OG.body(size: 14, weight: FontWeight.w500)),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
