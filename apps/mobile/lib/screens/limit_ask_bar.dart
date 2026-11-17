import 'package:flutter/material.dart';

import '../stores/about_store.dart';
import '../widgets/feeling_card.dart';

/// After a session: one small card per limit the session loaded, "How was the
/// <limit> today?", with a Skip. It sits in the page and never blocks it. It
/// shows nothing when there is nothing to ask.
class LimitAskBar extends StatelessWidget {
  const LimitAskBar({super.key, required this.about});

  final AboutStore about;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: about,
      builder: (BuildContext context, Widget? child) {
        if (about.asks.isEmpty) {
          return const SizedBox.shrink();
        }
        final AskPrompt p = about.asks.first;
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: FeelingCard(
            key: ValueKey<String>('ask-${p.sessionId}-${p.item.limitId}'),
            question: 'How was the ${p.item.title.toLowerCase()} today?',
            onAnswer: (String f) => about.answerAsk(p, f),
            onSkip: () => about.skipAsk(p),
          ),
        );
      },
    );
  }
}
