import 'package:flutter/material.dart';

import '../theme.dart';

/// A small, quiet mark: a pin and the name of the place. With no [name] it
/// shows a faint "Place", so the person can still tap it to set one. It stays
/// secondary: it must never compete with the title next to it.
class PlaceMark extends StatelessWidget {
  const PlaceMark({super.key, required this.name, required this.onTap});

  final String? name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool none = name == null || name!.trim().isEmpty;
    final Color color = none ? OG.mute.withValues(alpha: 0.55) : OG.mute;
    return Semantics(
      button: true,
      label: none ? 'Place' : 'Place: $name',
      child: InkWell(
        key: const ValueKey<String>('place-mark'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.place_outlined, size: 15, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  none ? 'Place' : name!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      OG.body(size: 14, weight: FontWeight.w500, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
