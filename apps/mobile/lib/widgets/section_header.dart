import 'package:flutter/material.dart';

import '../theme.dart';

/// Small upper-case section label with an optional blue action on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: OG.muted(size: 13, weight: FontWeight.w700).copyWith(letterSpacing: 0.8),
            ),
          ),
          if (action != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                alignment: Alignment.centerRight,
                child: Text(action!, style: OG.body(size: 15, weight: FontWeight.w800, color: OG.accent)),
              ),
            ),
        ],
      ),
    );
  }
}
