import 'package:flutter/material.dart';

import '../theme.dart';
import 'body_figure.dart';

/// The look of one chip of the session meta row: a small bordered pill.
BoxDecoration metaChipBox() => BoxDecoration(
      color: OG.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: OG.ink, width: 1.5),
    );

/// One tappable chip of the session meta row: an optional icon and a label.
class MetaItem extends StatelessWidget {
  const MetaItem({super.key, required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
          decoration: metaChipBox(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[Icon(icon, size: 16, color: OG.ink), const SizedBox(width: 6)],
              Text(label, style: OG.body(size: 14, weight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small figure at the right of the session title: what the planned
/// session works, front and back. A tap opens "Why this session". With no
/// [load] (offline, or not known yet) the figure is grey.
class WhyFigureButton extends StatelessWidget {
  const WhyFigureButton({super.key, required this.load, required this.onTap});

  final Map<String, int>? load;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Why this session',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Why this session',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
            decoration: BoxDecoration(
              color: OG.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OG.ink, width: 2),
            ),
            child: SizedBox(height: 54, child: BodyFigureMini(load: load ?? const <String, int>{})),
          ),
        ),
      ),
    );
  }
}

/// The small secondary row under the session title. It wraps when the items
/// do not fit one line. An optional [note] shows as a quiet line below.
class SessionMetaRow extends StatelessWidget {
  const SessionMetaRow({super.key, required this.items, this.note});

  final List<Widget> items;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final String? n = note;
    return SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: items,
            ),
            if (n != null)
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(n, style: OG.muted(size: 14))),
          ],
        ));
  }
}

/// The full focus and rationale text, for the "Why this session" sheet.
class WhySessionBody extends StatelessWidget {
  const WhySessionBody({super.key, this.focus, this.rationale, this.load});

  final String? focus;
  final String? rationale;

  /// Muscle key -> level 0..3 of the planned session. Null or all zero: no figure.
  final Map<String, int>? load;

  @override
  Widget build(BuildContext context) {
    final String? f = focus;
    final String? r = rationale;
    final Map<String, int>? l = load;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (l != null && l.values.any((int v) => v > 0)) ...<Widget>[
          Text('What it works', style: OG.muted(size: 14, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.6,
              child: BodyFigure(key: const ValueKey<String>('why-figure'), load: l, loadOnly: true, onTap: (String _) {}),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (f != null) ...<Widget>[
          Text('Focus', style: OG.muted(size: 14, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(f, style: OG.body(size: 17, weight: FontWeight.w600)),
          const SizedBox(height: 14),
        ],
        if (r != null) ...<Widget>[
          Text('Why', style: OG.muted(size: 14, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(r, style: OG.body(size: 17)),
        ],
      ],
    );
  }
}
