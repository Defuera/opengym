import 'package:flutter/material.dart';

import '../theme.dart';

/// Bottom sheet in the app style. [builder] makes the content; it scrolls and
/// keeps clear of the keyboard. Returns what the content pops.
///
/// With [scroll] false the content is a bounded column (it should scroll its
/// own middle part and keep the footer in view); the sheet is at most 88 % of
/// the screen high and shows a drag handle.
Future<T?> showOgSheet<T>(BuildContext context, WidgetBuilder builder, {bool scroll = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    constraints: scroll
        ? null
        : BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
    backgroundColor: OG.ground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: OG.ink, width: 2),
    ),
    builder: (BuildContext ctx) {
      final double keyboard = MediaQuery.of(ctx).viewInsets.bottom;
      if (!scroll) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 12 + keyboard),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: OG.mute.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Flexible(child: builder(ctx)),
              ],
            ),
          ),
        );
      }
      return SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 12 + keyboard),
          child: builder(ctx),
        ),
      );
    },
  );
}
