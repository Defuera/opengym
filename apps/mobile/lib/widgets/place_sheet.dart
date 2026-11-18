import 'package:flutter/material.dart';

import '../theme.dart';
import 'og_button.dart';
import 'og_sheet.dart';

/// One place in the list of the sheet.
class PlaceChoice {
  const PlaceChoice({required this.id, required this.name});

  final String id;
  final String name;
}

/// What the person did in the place sheet: picked a place, or asked to tell
/// the coach about the current one.
class PlaceSheetResult {
  const PlaceSheetResult.pick(this.placeId) : tell = false;
  const PlaceSheetResult.tell()
      : placeId = null,
        tell = true;

  final String? placeId;
  final bool tell;
}

/// The "Place" sheet: what the coach knows about the current place, the list
/// of places (the current one marked) and a button to tell the coach more.
/// [currentName] null means the session has no place: the knowledge block and
/// the button are hidden. [knowledge] is the place text; empty shows "Nothing yet.".
Future<PlaceSheetResult?> showPlaceSheet(
  BuildContext context, {
  required String? currentId,
  required String? currentName,
  required String knowledge,
  required List<PlaceChoice> places,
}) {
  return showOgSheet<PlaceSheetResult>(
    context,
    (BuildContext ctx) {
      final String text = knowledge.trim();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (currentName != null) ...<Widget>[
            Text('What the coach knows about $currentName',
                style: OG.muted(size: 14, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              text.isEmpty ? 'Nothing yet.' : text,
              key: const ValueKey<String>('place-text'),
              style: OG.body(size: 16),
            ),
            const SizedBox(height: 16),
          ],
          if (places.isNotEmpty) ...<Widget>[
            Text('Places', style: OG.muted(size: 14, weight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final PlaceChoice p in places) ...<Widget>[
              OgButton(
                minHeight: 48,
                variant: p.id == currentId ? OgVariant.accent : OgVariant.plain,
                onPressed: () =>
                    Navigator.of(ctx).pop(PlaceSheetResult.pick(p.id)),
                child: Row(
                  children: <Widget>[
                    Expanded(
                        child: Text(p.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (p.id == currentId) const Icon(Icons.check, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
          ],
          if (currentName != null)
            OgButton(
              variant: OgVariant.dashed,
              onPressed: () =>
                  Navigator.of(ctx).pop(const PlaceSheetResult.tell()),
              child: const Text('Tell the coach about this place'),
            ),
        ],
      );
    },
    title: 'Place',
  );
}
