import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_icon_button.dart';

/// Share of the screen a sheet may fill. The rest stays visible, so a tap there closes the sheet.
const double ogSheetMaxHeight = 0.9;

/// The one bottom sheet of the app. Every sheet closes three ways: drag it down,
/// tap outside it, or tap the X (top right). It has a drag handle and a header
/// row with the optional [title] and the X.
///
/// [builder] makes the content. By default the content scrolls inside the sheet
/// and keeps clear of the keyboard; the handle and the header stay put and drag
/// the sheet. With [scroll] false the content is a bounded column (it should
/// scroll its own middle part and keep the footer in view). Returns what the
/// content pops (the X and a drag pop null).
Future<T?> showOgSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  String? title,
  bool scroll = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * ogSheetMaxHeight),
    backgroundColor: OG.ground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: OG.ink, width: 2),
    ),
    builder: (BuildContext ctx) => _OgSheetBody(title: title, scroll: scroll, builder: builder),
  );
}

class _OgSheetBody extends StatelessWidget {
  const _OgSheetBody({required this.title, required this.scroll, required this.builder});

  final String? title;
  final bool scroll;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                key: const ValueKey<String>('og-sheet-handle'),
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: OG.mute.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: title == null
                        ? const SizedBox.shrink()
                        : Text(title!,
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: OG.display(24)),
                  ),
                  const SizedBox(width: 12),
                  KeyedSubtree(
                    key: const ValueKey<String>('og-sheet-close'),
                    child: OgIconButton(
                      icon: Icons.close,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: scroll
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: builder(context),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: builder(context),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
