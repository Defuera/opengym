import 'package:flutter/material.dart';

import '../theme.dart';

/// A muted time with the category after it, in the category's colour:
/// "Today, 10:46 · Meal". Without a category it is the time alone.
class CategoryWhen extends StatelessWidget {
  const CategoryWhen({super.key, required this.when, this.category, this.size = 17});

  final String when;
  final String? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? c = category;
    if (c == null) {
      return Text(when, style: OG.muted(size: size));
    }
    return Text.rich(
      TextSpan(
        style: OG.muted(size: size),
        children: <InlineSpan>[
          TextSpan(text: '$when · '),
          TextSpan(text: c, style: OG.body(size: size, weight: FontWeight.w700, color: OG.categoryColor(c))),
        ],
      ),
    );
  }
}
