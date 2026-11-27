import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'attachment_strip.dart';
import 'voice_wave.dart';

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
    this.onSend,
    this.onAttach,
    this.showText = true,
    this.maxLength,
    this.attachments = const <StripItem>[],
    this.onRemoveAttachment,
    this.sending = false,
    this.offlineNote,
    this.quietNote,
    this.hint = 'Message',
    this.onMic,
    this.onCamera,
    this.attachOff = false,
    this.sendLabel = 'Send',
    this.sendWhenEmpty = false,
    this.recording = false,
    this.recordSeconds = 0,
    this.onCancelRecording,
    this.onStopRecording,
    this.voiceNote,
    this.recordLevels = const <double>[],
    this.transcribing = false,
    this.onRetryVoice,
    this.onDiscardVoice,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  /// Null: no send button. A screen that has its own action button (the Start step) uses this.
  final VoidCallback? onSend;

  /// Opens the attach sheet (library, camera, file). Null: no "+" button.
  final VoidCallback? onAttach;

  /// The most characters the field takes (no counter shows). Null: no limit.
  final int? maxLength;

  /// False: no text field. Only for a screen whose input has no text (the import of files).
  final bool showText;
  final List<StripItem> attachments;
  final ValueChanged<int>? onRemoveAttachment;
  final bool sending;

  /// When set, the composer is off and shows this note (no connection).
  final String? offlineNote;

  /// A quiet line above the field. It does not turn anything off (the chat:
  /// "Offline. Messages are sent when the connection is back.").
  final String? quietNote;
  final String hint;

  /// Starts a voice recording. Null: the composer has no mic button. The mic
  /// shows in the place of send while the field is empty and nothing is attached.
  /// With attachments and an empty field it shows left of send. With typed text it is gone.
  final VoidCallback? onMic;

  /// Opens the camera at once (one tap, no sheet). Null: no camera button.
  final VoidCallback? onCamera;

  /// True: the "+" and the camera show but do not work (a file needs the link and there is none). The text, the mic and send stay as they are.
  final bool attachOff;

  /// What a screen reader says for the send button ("Save" where send saves a comment).
  final String sendLabel;

  /// True: send works with an empty field and nothing attached (a screen where an empty save removes something).
  final bool sendWhenEmpty;

  /// True: the composer is a recording bar (red dot, timer, cancel, stop and send).
  final bool recording;
  final int recordSeconds;
  final VoidCallback? onCancelRecording;
  final VoidCallback? onStopRecording;

  /// A quiet line above the field (for example: the microphone is not allowed).
  final String? voiceNote;

  /// Recent loudness while recording, 0..1, newest last (the wave).
  final List<double> recordLevels;

  /// True: the recording is being turned into text. The field is replaced by a
  /// quiet "Transcribing…" line and the mic is off.
  final bool transcribing;

  /// Set with [voiceNote] when the same recording can be read again.
  final VoidCallback? onRetryVoice;

  /// Drops the kept recording (the close mark next to the retry). While
  /// transcribing it is the cancel button.
  final VoidCallback? onDiscardVoice;

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
          if (quietNote != null) ...<Widget>[
            Text(quietNote!, key: const ValueKey<String>('composer-quiet-note'), style: OG.muted(size: 14)),
            const SizedBox(height: 8),
          ],
          if (voiceNote != null && !recording && !transcribing) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(voiceNote!, key: const ValueKey<String>('voice-note'), style: OG.muted(size: 14))),
                if (onRetryVoice != null)
                  GestureDetector(
                    key: const ValueKey<String>('voice-retry'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onRetryVoice,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Text('Try again', style: OG.body(size: 14, weight: FontWeight.w700).copyWith(color: OG.accent)),
                    ),
                  ),
                if (onDiscardVoice != null)
                  GestureDetector(
                    key: const ValueKey<String>('voice-discard'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onDiscardVoice,
                    child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.close, size: 18)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          if (attachments.isNotEmpty) ...<Widget>[
            // Stays while recording and transcribing; the person can still see what goes with the text, but cannot remove it then.
            AttachmentStrip(
              items: attachments,
              onRemove: (recording || transcribing) ? null : (int i) => onRemoveAttachment?.call(i),
            ),
            const SizedBox(height: 6),
          ],
          Container(
            decoration: BoxDecoration(
              color: OG.ground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OG.ink, width: OG.borderWidth),
            ),
            child: recording ? _recordingRow() : transcribing ? _transcribingRow() : Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (showText)
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !off,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: maxLength,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  textCapitalization: TextCapitalization.sentences,
                  style: OG.body(),
                  decoration: InputDecoration(
                    hintText: off ? 'Offline' : hint,
                    hintStyle: OG.muted(),
                    counterText: '',
                    isDense: true,
                    contentPadding: EdgeInsets.fromLTRB(14, 12, 14, (onAttach != null || onCamera != null || onSend != null || onMic != null) ? 4 : 12),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
                if (onAttach != null || onCamera != null || onSend != null || onMic != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
                  child: Row(
                    children: <Widget>[
                      if (onAttach != null)
                        _RoundTap(
                          key: const ValueKey<String>('composer-plus'),
                          icon: Icons.add,
                          onTap: (off || attachOff) ? null : onAttach,
                        ),
                      if (onCamera != null)
                        _RoundTap(
                          key: const ValueKey<String>('composer-camera'),
                          icon: Icons.photo_camera_outlined,
                          onTap: (off || attachOff) ? null : onCamera,
                        ),
                      const Spacer(),
                      if (onSend != null || onMic != null)
                      ListenableBuilder(
                        listenable: controller,
                        builder: (BuildContext c, Widget? w) {
                          final bool hasText = controller.text.trim().isNotEmpty;
                          final bool ready = hasText || attachments.isNotEmpty || sendWhenEmpty;
                          final Widget mic = _RoundTap(
                            key: const ValueKey<String>('composer-mic'),
                            icon: Icons.mic_none,
                            onTap: off ? null : onMic,
                          );
                          if (onSend == null || (!ready && !sending && onMic != null)) {
                            return onMic == null ? const SizedBox.shrink() : mic;
                          }
                          final Widget send = _SendTap(
                            label: sendLabel,
                            sending: sending,
                            onTap: (sending || off || !ready) ? null : onSend,
                          );
                          // Attachments and an empty field: the mic stays beside send, so the person can still speak the comment.
                          if (onMic != null && !sending && !hasText) {
                            return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[mic, send]);
                          }
                          return send;
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

  /// Same frame, one quiet row while the text is fetched: a small spinner,
  /// "Transcribing…", and cancel at the right. The mic is not there.
  Widget _transcribingRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: OG.mute),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Transcribing…', key: const ValueKey<String>('transcribing'), style: OG.muted())),
          _RoundTap(
            key: const ValueKey<String>('composer-cancel-transcribe'),
            icon: Icons.close,
            onTap: onDiscardVoice,
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
          const SizedBox(width: 10),
          Expanded(child: VoiceWave(key: const ValueKey<String>('record-wave'), levels: recordLevels)),
          const SizedBox(width: 10),
          _SendTap(
            label: 'Stop recording',
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
    this.label = 'Send',
    required this.sending,
    required this.onTap,
    this.buttonKey = const ValueKey<String>('composer-send'),
  });

  final Key buttonKey;
  final String label;

  final bool sending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool on = onTap != null;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
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
      ),
    );
  }
}
