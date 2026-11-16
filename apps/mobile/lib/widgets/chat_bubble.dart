import 'package:flutter/material.dart';

import '../theme.dart';

/// One chat message. Mine on the right (accent), the coach's on the left.
/// [sources] adds a muted "Also read: ..." line under a coach message.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.mine,
    this.sources = const <String>[],
    this.attachments = const <String>[],
  });

  final String text;
  final bool mine;
  final List<String> sources;
  final List<String> attachments;

  @override
  Widget build(BuildContext context) {
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
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
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
    );
  }
}
