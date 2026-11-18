import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Round check control at the right end of a set row or card header.
/// Open: empty outlined circle, tap completes. Done: filled, tap undoes.
/// The circle is 34 pt; the tap target is 44 x 44.
class SetCheck extends StatelessWidget {
  const SetCheck({super.key, required this.done, required this.onTap});

  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: done ? 'Undo set' : 'Complete set',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (done) {
            HapticFeedback.lightImpact();
          } else {
            HapticFeedback.mediumImpact();
          }
          onTap();
        },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? OG.ink : Colors.transparent,
                border: Border.all(color: OG.ink, width: 2),
              ),
              child: Icon(Icons.check, size: 20, color: done ? OG.white : OG.ink),
            ),
          ),
        ),
      ),
    );
  }
}
