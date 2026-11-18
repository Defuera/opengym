import 'package:flutter/material.dart';

import '../theme.dart';

/// One quiet tappable item of the session meta row.
class MetaItem extends StatelessWidget {
  const MetaItem({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Text(label,
              style:
                  OG.body(size: 14, weight: FontWeight.w500, color: OG.mute)),
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
              spacing: 14,
              runSpacing: 0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: items,
            ),
            if (n != null)
              Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(n, style: OG.muted(size: 14))),
          ],
        ));
  }
}

/// The full focus and rationale text, for the "Why this session" sheet.
class WhySessionBody extends StatelessWidget {
  const WhySessionBody({super.key, this.focus, this.rationale});

  final String? focus;
  final String? rationale;

  @override
  Widget build(BuildContext context) {
    final String? f = focus;
    final String? r = rationale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
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
