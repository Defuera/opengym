import 'package:flutter/material.dart';

import '../models.dart';
import '../stores/coach_store.dart';
import '../widgets/og_button.dart';
import '../widgets/og_sheet.dart';
import '../widgets/thread_card.dart';

/// The chat list as a sheet over the chat: pick a chat, or start a new one.
Future<void> showChatThreadsSheet(
  BuildContext context, {
  required CoachStore coach,
  required bool canStartNew,
}) {
  return showOgSheet<void>(
    context,
    (BuildContext ctx) {
      final List<Widget> rows = <Widget>[];
      for (final Thread t in coach.threads) {
        rows.add(ThreadCard(
          title: t.title,
          lastMessage: t.thinking ? 'Coach is thinking…' : t.lastMessage,
          onTap: () {
            Navigator.of(ctx).pop();
            coach.openThread(t.id);
          },
        ));
        rows.add(const SizedBox(height: 10));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OgButton(
            key: const ValueKey<String>('chats-new'),
            variant: OgVariant.accent,
            onPressed: canStartNew
                ? () {
                    Navigator.of(ctx).pop();
                    coach.startNewChat();
                  }
                : null,
            child: const Text('New chat'),
          ),
          const SizedBox(height: 14),
          ...rows,
        ],
      );
    },
    title: 'Chats',
  );
}
