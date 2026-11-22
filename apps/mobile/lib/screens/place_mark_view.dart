import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../widgets/place_mark.dart';
import '../widgets/place_sheet.dart';
import 'chat_screen.dart';

/// The place mark of one session. It follows the places store, so a name or a
/// note the coach changes shows at once. A tap opens the "Place" sheet:
/// [onPick] gets the place the person chose; "Tell the coach" opens a chat
/// about the current place.
class PlaceMarkView extends StatelessWidget {
  const PlaceMarkView({super.key, required this.deps, required this.placeId, required this.onPick, this.chip = false});

  /// See [PlaceMark.chip].
  final bool chip;

  final AppDeps deps;
  final String? placeId;
  final void Function(String placeId) onPick;

  Future<void> _open(BuildContext context) async {
    final Place? cur = deps.places.byId(placeId);
    final PlaceSheetResult? r = await showPlaceSheet(
      context,
      currentId: placeId,
      currentName: placeId == null ? null : (cur?.name ?? 'this place'),
      knowledge: cur?.text ?? '',
      places: <PlaceChoice>[for (final Place p in deps.places.places) PlaceChoice(id: p.id, name: p.name)],
    );
    if (r == null) {
      return;
    }
    if (!r.tell) {
      onPick(r.placeId!);
      return;
    }
    if (!context.mounted) {
      return;
    }
    await deps.coach.startNewChat(placeId: placeId, title: 'About ${cur?.name ?? 'this place'}');
    if (context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (BuildContext c) => ChatScreen(deps: deps)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: deps.places,
      builder: (BuildContext context, Widget? child) =>
          PlaceMark(name: deps.places.byId(placeId)?.name, chip: chip, onTap: () => _open(context)),
    );
  }
}
