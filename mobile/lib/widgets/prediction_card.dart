import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';

/// The big accent "most likely" card.
class PredictionCard extends StatelessWidget {
  const PredictionCard({
    super.key,
    required this.rankLabel,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String rankLabel;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OgButton(
      variant: OgVariant.accent,
      minHeight: 170,
      radius: 20,
      padding: const EdgeInsets.all(20),
      alignment: Alignment.topLeft,
      onPressed: onTap,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  rankLabel,
                  style: OG.body(weight: FontWeight.w600, color: OG.white),
                ),
                const Icon(Icons.arrow_forward, size: 28),
              ],
            ),
            const SizedBox(height: 40),
            Text(title, style: OG.display(44, color: OG.white)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: OG.body(weight: FontWeight.w500, color: OG.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// Smaller choice card: a rank number (or icon) above a display title.
class OptionCard extends StatelessWidget {
  const OptionCard({
    super.key,
    required this.title,
    required this.onTap,
    this.number,
    this.icon,
    this.dashed = false,
    this.subtitle,
  });

  final String title;
  final VoidCallback? onTap;
  final String? number;
  final IconData? icon;
  final bool dashed;

  /// Muted reason line under the title.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final String? n = number;
    final IconData? i = icon;
    final String? sub = subtitle;
    return OgButton(
      variant: dashed ? OgVariant.dashed : OgVariant.plain,
      minHeight: 112,
      padding: const EdgeInsets.all(14),
      alignment: Alignment.topLeft,
      onPressed: onTap,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (n != null) Text(n, style: OG.muted(weight: FontWeight.w700)),
            if (i != null) Icon(i, size: 26),
            const SizedBox(height: 18),
            Text(title, style: OG.display(24)),
            if (sub != null && sub.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(sub, style: OG.muted(size: 14)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Two-column grid of equally sized cards.
class OptionGrid extends StatelessWidget {
  const OptionGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i += 2) {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: children[i]),
          const SizedBox(width: 12),
          Expanded(
            child: i + 1 < children.length ? children[i + 1] : const SizedBox(),
          ),
        ],
      ));
      rows.add(const SizedBox(height: 8));
    }
    return Column(children: rows);
  }
}
