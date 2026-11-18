import 'package:flutter/material.dart';

import '../theme.dart';

/// Muted label above a bordered text field.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.obscure = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.helper,
    this.readOnly = false,
    this.autocorrect = false,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  /// Shown above the field; none when the hint says enough.
  final String? label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final bool obscure;
  final int maxLines;
  final int? minLines;

  /// Hard character limit. The counter is not shown; the helper says what the field is for.
  final int? maxLength;
  final String? helper;
  final bool readOnly;
  final bool autocorrect;
  final TextInputAction? textInputAction;
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
        if (label != null) ...<Widget>[
          Text(label!, style: OG.muted(size: 14, weight: FontWeight.w600)),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          maxLines: obscure ? 1 : maxLines,
          minLines: obscure ? null : minLines,
          maxLength: maxLength,
          readOnly: readOnly,
          textInputAction: textInputAction,
          autocorrect: autocorrect,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: OG.body(),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: OG.muted(),
            counterText: maxLength == null ? null : '',
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
        if (helper != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(helper!, style: OG.muted(size: 14)),
        ],
      ],
    );
  }
}
