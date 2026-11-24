import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'chat_markup.dart';
import 'og_button.dart';

/// One chat message. Mine on the right (accent), the coach's on the left.
/// A coach message shows its simple formatting (bold, bullets, line breaks).
/// A long press copies the text and shows "Copied" for a moment.
class ChatBubble extends StatefulWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.mine,
    this.attachments = const <String>[],
    this.media = const <Widget>[],
    this.copyable = true,
    this.voice,
    this.voiceFailedText = 'Could not read the recording.',
    this.onRetryVoice,
  });

  final String text;
  final bool mine;
  final List<String> attachments;

  /// Thumbnails or file chips of what was sent. They replace the "Attached" line.
  final List<Widget> media;
  final bool copyable;

  /// Set on a voice message: pending | done | failed. It shows a small mic
  /// icon; pending says "Listening…", failed says [voiceFailedText] with a
  /// "Try again" action ([onRetryVoice]).
  final String? voice;
  final String voiceFailedText;
  final VoidCallback? onRetryVoice;

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _copied = false;
  Timer? _timer;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<Widget> _voiceBody(Color fg) {
    final String v = widget.voice ?? '';
    final Widget mic = Padding(
      padding: const EdgeInsets.only(top: 3, right: 8),
      child: Icon(Icons.mic_none, size: 16, color: fg),
    );
    if (v == 'failed') {
      return <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[mic, Flexible(child: Text(widget.voiceFailedText, style: OG.body(color: fg)))],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OgButton(
          key: const ValueKey<String>('voice-retry'),
          onPressed: widget.onRetryVoice,
          minHeight: 44,
          radius: 12,
          shadow: false,
          child: const Text('Try again'),
          ),
        ),
      ];
    }
    final bool pending = v == 'pending';
    return <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          mic,
          Flexible(
            child: Text(
              pending ? 'Listening…' : widget.text,
              style: pending
                  ? OG.body(color: fg).copyWith(fontStyle: FontStyle.italic)
                  : OG.body(color: fg),
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final String text = widget.text;
    final bool mine = widget.mine;
    final List<String> attachments = widget.attachments;
    final Color fg = mine ? OG.white : OG.ink;
    final List<Widget> body = <Widget>[];
    if (widget.media.isNotEmpty) {
      body.add(Wrap(spacing: 6, runSpacing: 6, children: widget.media));
      if (text.isNotEmpty || widget.voice != null) {
        body.add(const SizedBox(height: 8));
      }
    }
    if (widget.voice != null) {
      body.addAll(_voiceBody(fg));
    } else if (text.isNotEmpty || widget.media.isEmpty) {
      body.add(mine ? Text(text, style: OG.body(color: fg)) : chatMarkup(text, OG.body(color: fg)));
    }
    if (attachments.isNotEmpty && widget.media.isEmpty) {
      body.add(const SizedBox(height: 6));
      body.add(Text(
        'Attached: ${attachments.join(', ')}',
        style: OG.body(size: 13, color: fg),
      ));
    }
    if (_copied) {
      body.add(const SizedBox(height: 6));
      body.add(Text('Copied', style: OG.body(size: 13, color: fg).copyWith(fontWeight: FontWeight.w700)));
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.86,
        ),
        child: GestureDetector(
          onLongPress: widget.copyable ? _copy : null,
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: ogBox(
            color: mine ? OG.accent : OG.card,
            radius: 18,
            offset: 3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: body,
          ),
          ),
        ),
      ),
    );
  }
}
