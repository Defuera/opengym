import 'package:flutter/material.dart';

import '../theme.dart';

/// A small, quiet mark: a pin and the name of the place. With no [name] it
/// shows a faint "Place", so the person can still tap it to set one. It stays
/// secondary: it must never compete with the title next to it.
class PlaceMark extends StatelessWidget {
  const PlaceMark({super.key, required this.name, required this.onTap, this.chip = false});

  final String? name;
  final VoidCallback onTap;

  /// A bordered pill with ink text, for the meta row of the open session. Off: the quiet mark.
  final bool chip;

  @override
  Widget build(BuildContext context) {
    final bool none = name == null || name!.trim().isEmpty;
    final Color color = chip ? (none ? OG.mute : OG.ink) : (none ? OG.mute.withValues(alpha: 0.55) : OG.mute);
    return Semantics(
      button: true,
      label: none ? 'Place' : 'Place: $name',
      child: InkWell(
        key: const ValueKey<String>('place-mark'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(chip ? 18 : 8),
        child: Container(
          padding: chip
              ? const EdgeInsets.symmetric(vertical: 7, horizontal: 12)
              : const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: chip
              ? BoxDecoration(
                  color: OG.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: OG.ink, width: 1.5),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.place_outlined, size: chip ? 16 : 15, color: color),
              SizedBox(width: chip ? 6 : 4),
              Flexible(
                child: Text(
                  none ? 'Place' : name!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OG.body(size: 14, weight: chip ? FontWeight.w600 : FontWeight.w500, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
