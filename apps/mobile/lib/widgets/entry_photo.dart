import 'package:flutter/material.dart';

import '../theme.dart';

/// A photo from an address. When it cannot load, a framed note names the file.
class EntryPhoto extends StatelessWidget {
  const EntryPhoto({super.key, required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final String? u = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(OG.radius),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: OG.ink, width: OG.borderWidth),
          borderRadius: BorderRadius.circular(OG.radius),
        ),
        child: u == null
            ? _missing()
            : Image.network(
                u,
                width: double.infinity,
                fit: BoxFit.fitWidth,
                errorBuilder: (BuildContext c, Object e, StackTrace? s) => _missing(),
              ),
      ),
    );
  }

  Widget _missing() {
    return Container(
      width: double.infinity,
      color: OG.soft,
      padding: const EdgeInsets.all(18),
      child: Text('$name: the photo cannot be shown now.', style: OG.muted()),
    );
  }
}
