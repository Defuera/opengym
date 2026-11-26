import 'package:flutter/material.dart';

import '../theme.dart';
import 'chat_bubble.dart';
import 'coach_turn_parts.dart';
import 'sheet_link.dart';

/// The coach's debrief of a finished session (ADR-041): a coach bubble with
/// the evaluation, the one question under it with its quick answers, and a way
/// to reply in the chat. Once the person answered, only the bubble and a link
/// "Continue in chat" show.
class DebriefCard extends StatelessWidget {
  const DebriefCard({
    super.key,
    required this.message,
    this.question,
    this.answers = const <(String, String)>[],
    this.answered = false,
    this.enabled = true,
    this.failed = false,
    required this.onAnswer,
    required this.onOpenChat,
  });

  /// The coach's words.
  final String message;

  /// The question text, and its quick answers as (id, label).
  final String? question;
  final List<(String, String)> answers;

  /// The person replied in the debrief chat already.
  final bool answered;

  /// False while the chat is being opened.
  final bool enabled;

  /// The chat could not be opened (no connection).
  final bool failed;

  /// A tap on a quick answer: the label is the first message of the chat.
  final void Function(String id, String label) onAnswer;

  /// Opens the debrief chat to type or speak a reply, or to go on.
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final String? q = question;
    return Column(
      key: const ValueKey<String>('debrief'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ChatBubble(text: message, mine: false),
        if (q != null && !answered) ...<Widget>[
          const SizedBox(height: 12),
          QuestionBlock(text: q, answers: answers, enabled: enabled, onAnswer: onAnswer),
        ],
        if (failed) ...<Widget>[
          const SizedBox(height: 8),
          Text('No connection. Try again when you are online.', key: const ValueKey<String>('debrief-failed'), style: OG.muted(size: 14)),
        ],
        SheetLink(
          key: ValueKey<String>(answered ? 'debrief-continue' : 'debrief-reply'),
          label: answered ? 'Continue in chat' : 'Reply to your coach',
          onTap: onOpenChat,
        ),
      ],
    );
  }
}

/// The quiet line in the place of the debrief while the coach is still
/// writing it, so the screen below does not jump.
class DebriefPending extends StatelessWidget {
  const DebriefPending({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey<String>('debrief-pending'),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text('The coach is looking at your session…', style: OG.muted().copyWith(fontStyle: FontStyle.italic)),
    );
  }
}
