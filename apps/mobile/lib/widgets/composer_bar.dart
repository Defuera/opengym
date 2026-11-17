import 'package:flutter/material.dart';

import '../theme.dart';
import 'attachment_chip.dart';
import 'og_button.dart';

/// Chat input: attachment chips, a text field, attach file / photo, send.
class ComposerBar extends StatelessWidget {
  const ComposerBar({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttachFile,
    required this.onAttachPhoto,
    this.attachmentNames = const <String>[],
    this.onRemoveAttachment,
    this.sending = false,
    this.offlineNote,
    this.hint = 'Tell the coach something, or ask',
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttachFile;
  final VoidCallback onAttachPhoto;
  final List<String> attachmentNames;
  final ValueChanged<int>? onRemoveAttachment;
  final bool sending;

  /// When set, the composer is off and shows this note (no connection).
  final String? offlineNote;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: OG.ink, width: OG.borderWidth),
    );
    final List<Widget> chips = <Widget>[];
    for (int i = 0; i < attachmentNames.length; i++) {
      chips.add(AttachmentChip(
        name: attachmentNames[i],
        onRemove: () {
          final ValueChanged<int>? cb = onRemoveAttachment;
          if (cb != null) {
            cb(i);
          }
        },
      ));
    }
    final String? offline = offlineNote;
    final bool off = offline != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: OG.card,
        border: Border(top: BorderSide(color: OG.ink, width: 2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (offline != null) ...<Widget>[
            Text(offline, style: OG.body(size: 14, weight: FontWeight.w600)),
            const SizedBox(height: 8),
          ],
          if (chips.isNotEmpty) ...<Widget>[
            Wrap(spacing: 6, runSpacing: 6, children: chips),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              _Square(icon: Icons.attach_file, onTap: onAttachFile),
              const SizedBox(width: 8),
              _Square(icon: Icons.photo_camera_outlined, onTap: onAttachPhoto),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !off,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  style: OG.body(),
                  decoration: InputDecoration(
                    hintText: off ? 'Offline' : hint,
                    hintStyle: OG.muted(),
                    filled: true,
                    fillColor: OG.ground,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                    border: border,
                    enabledBorder: border,
                    focusedBorder: border,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 56,
                child: OgButton(
                  variant: OgVariant.accent,
                  minHeight: 52,
                  padding: EdgeInsets.zero,
                  onPressed: (sending || off) ? null : onSend,
                  child: sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: OG.white,
                          ),
                        )
                      : const Icon(Icons.arrow_upward, size: 26),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Square extends StatelessWidget {
  const _Square({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: OgButton(
        minHeight: 52,
        padding: EdgeInsets.zero,
        shadow: false,
        onPressed: onTap,
        child: Icon(icon, size: 24),
      ),
    );
  }
}
