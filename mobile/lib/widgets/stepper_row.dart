import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Label, then big minus button (76x76), large number, big plus button.
class StepperRow extends StatelessWidget {
  const StepperRow({
    super.key,
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: OG.muted(size: 14, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            _StepButton(icon: Icons.remove, onTap: onMinus),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                  style: OG.display(60),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _StepButton(icon: Icons.add, onTap: onPlus),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatefulWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (TapDownDetails d) => setState(() => _down = true),
      onTapUp: (TapUpDetails d) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: Container(
        width: 76,
        height: 76,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _down ? OG.ink : OG.soft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: OG.ink, width: OG.borderWidth),
        ),
        child: Icon(widget.icon, size: 34, color: _down ? OG.white : OG.ink),
      ),
    );
  }
}
