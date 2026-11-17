import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// One chat message. Mine on the right (accent), the coach's on the left.
/// [sources] adds a muted "Also read: ..." line under a coach message.
/// A long press copies the text and shows "Copied" for a moment.
class ChatBubble extends StatefulWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.mine,
    this.sources = const <String>[],
    this.attachments = const <String>[],
    this.copyable = true,
  });

  final String text;
  final bool mine;
  final List<String> sources;
  final List<String> attachments;
  final bool copyable;

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

  @override
  Widget build(BuildContext context) {
    final String text = widget.text;
    final bool mine = widget.mine;
    final List<String> sources = widget.sources;
    final List<String> attachments = widget.attachments;
    final Color fg = mine ? OG.white : OG.ink;
    final List<Widget> body = <Widget>[
      Text(text, style: OG.body(color: fg)),
    ];
    if (attachments.isNotEmpty) {
      body.add(const SizedBox(height: 6));
      body.add(Text(
        'Attached: ${attachments.join(', ')}',
        style: OG.body(size: 13, color: fg),
      ));
    }
    if (!mine && sources.isNotEmpty) {
      body.add(const SizedBox(height: 8));
      body.add(Text('Also read: ${sources.join(', ')}', style: OG.muted(size: 13)));
    }
    if (_copied) {
      body.add(const SizedBox(height: 6));
      body.add(Text('Copied', style: OG.body(size: 13, color: fg).copyWith(fontWeight: FontWeight.w700)));
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
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
