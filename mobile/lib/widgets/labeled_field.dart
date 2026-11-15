import 'package:flutter/material.dart';

import '../theme.dart';

/// Muted label above a bordered text field.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.obscure = false,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final bool obscure;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final OutlineInputBorder idle = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: OG.ink, width: OG.borderWidth),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: OG.muted(size: 14, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          maxLines: obscure ? 1 : maxLines,
          autocorrect: false,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: OG.body(),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: OG.muted(),
            filled: true,
            fillColor: OG.card,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: idle,
            enabledBorder: idle,
            focusedBorder: idle.copyWith(
              borderSide: const BorderSide(color: OG.accent, width: 3),
            ),
          ),
        ),
      ],
    );
  }
}
