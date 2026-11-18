import 'package:flutter/material.dart';

import '../theme.dart';
import 'attachment_strip.dart';

/// The red of the recording dot (the same red as the limit and status marks).
const Color _recordRed = Color(0xFFE5482D);

/// Chat input, full width. Above the field: what is attached (only when
/// something is). The field grows from 1 to 5 lines. Under the text, inside
/// the same frame: "+" at the left (opens the attach sheet) and send at the right.
class ComposerBar extends StatelessWidget {
  const ComposerBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.onSend,
    required this.onAttach,
    this.attachments = const <StripItem>[],
    this.onRemoveAttachment,
    this.sending = false,
    this.offlineNote,
    this.hint = 'Message',
    this.onMic,
    this.recording = false,
    this.recordSeconds = 0,
    this.onCancelRecording,
    this.onStopRecording,
    this.voiceNote,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final List<StripItem> attachments;
  final ValueChanged<int>? onRemoveAttachment;
  final bool sending;

  /// When set, the composer is off and shows this note (no connection).
  final String? offlineNote;
  final String hint;

  /// Starts a voice recording. Null: the composer has no mic button. The mic
  /// shows in the place of send while the field is empty and nothing is attached.
  final VoidCallback? onMic;

  /// True: the composer is a recording bar (red dot, timer, cancel, stop and send).
  final bool recording;
  final int recordSeconds;
  final VoidCallback? onCancelRecording;
  final VoidCallback? onStopRecording;

  /// A quiet line above the field (for example: the microphone is not allowed).
  final String? voiceNote;

  @override
  Widget build(BuildContext context) {
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
          if (voiceNote != null && !recording) ...<Widget>[
            Text(voiceNote!, key: const ValueKey<String>('voice-note'), style: OG.muted(size: 14)),
            const SizedBox(height: 8),
          ],
          if (attachments.isNotEmpty && !recording) ...<Widget>[
            AttachmentStrip(
              items: attachments,
              onRemove: (int i) => onRemoveAttachment?.call(i),
            ),
            const SizedBox(height: 6),
          ],
          Container(
            decoration: BoxDecoration(
              color: OG.ground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OG.ink, width: OG.borderWidth),
            ),
            child: recording ? _recordingRow() : Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !off,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: OG.body(),
                  decoration: InputDecoration(
                    hintText: off ? 'Offline' : hint,
                    hintStyle: OG.muted(),
                    isDense: true,
                    contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
                  child: Row(
                    children: <Widget>[
                      _RoundTap(
                        key: const ValueKey<String>('composer-plus'),
                        icon: Icons.add,
                        onTap: off ? null : onAttach,
                      ),
                      const Spacer(),
                      ListenableBuilder(
                        listenable: controller,
                        builder: (BuildContext c, Widget? w) {
                          final bool ready =
                              controller.text.trim().isNotEmpty || attachments.isNotEmpty;
                          if (!ready && !sending && onMic != null) {
                            return _RoundTap(
                              key: const ValueKey<String>('composer-mic'),
                              icon: Icons.mic_none,
                              onTap: off ? null : onMic,
                            );
                          }
                          return _SendTap(
                            sending: sending,
                            onTap: (sending || off || !ready) ? null : onSend,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Same frame, one row: cancel at the left, a red dot and the timer, then
  /// stop-and-send (accent) at the right, in the place of the send button.
  Widget _recordingRow() {
    final String time = '${recordSeconds ~/ 60}:${(recordSeconds % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(
        children: <Widget>[
          _RoundTap(
            key: const ValueKey<String>('composer-cancel-record'),
            icon: Icons.close,
            onTap: onCancelRecording,
          ),
          const SizedBox(width: 10),
          Container(
            key: const ValueKey<String>('record-dot'),
            width: 10,
            height: 10,
            decoration: const BoxDecoration(color: _recordRed, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            time,
            key: const ValueKey<String>('record-time'),
            style: OG.body(weight: FontWeight.w600).copyWith(fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]),
          ),
          const Spacer(),
          _SendTap(
            sending: false,
            onTap: onStopRecording,
            buttonKey: const ValueKey<String>('composer-stop-record'),
          ),
        ],
      ),
    );
  }
}

/// 36 px to look, 44 px to tap.
class _RoundTap extends StatelessWidget {
  const _RoundTap({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Opacity(
            opacity: onTap == null ? 0.35 : 1,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: OG.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OG.ink, width: OG.borderWidth),
              ),
              child: Icon(icon, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class _SendTap extends StatelessWidget {
  const _SendTap({
    required this.sending,
    required this.onTap,
    this.buttonKey = const ValueKey<String>('composer-send'),
  });

  final Key buttonKey;

  final bool sending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool on = onTap != null;
    return GestureDetector(
      key: buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: on || sending ? OG.accent : OG.soft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on || sending ? OG.ink : OG.mute, width: OG.borderWidth),
            ),
            child: sending
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 3, color: OG.white),
                  )
                : Icon(Icons.arrow_upward, size: 22, color: on ? OG.white : OG.mute),
          ),
        ),
      ),
    );
  }
}
