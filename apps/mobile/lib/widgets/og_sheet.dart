import 'package:flutter/material.dart';

import '../theme.dart';

/// Bottom sheet in the app style. [builder] makes the content; it scrolls and
/// keeps clear of the keyboard. Returns what the content pops.
Future<T?> showOgSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: OG.ground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: OG.ink, width: 2),
    ),
    builder: (BuildContext ctx) {
      final double keyboard = MediaQuery.of(ctx).viewInsets.bottom;
      return SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 12 + keyboard),
          child: builder(ctx),
        ),
      );
    },
  );
}
