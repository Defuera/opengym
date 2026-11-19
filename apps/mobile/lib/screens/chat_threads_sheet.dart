import 'package:flutter/material.dart';

import '../models.dart';
import '../stores/coach_store.dart';
import '../widgets/og_button.dart';
import '../widgets/og_sheet.dart';
import '../widgets/show_all_row.dart';
import '../widgets/thread_card.dart';

/// The chat list as a sheet over the chat: pick a chat, or start a new one.
Future<void> showChatThreadsSheet(
  BuildContext context, {
  required CoachStore coach,
  required bool canStartNew,
}) {
  return showOgSheet<void>(
    context,
    (BuildContext ctx) => ListenableBuilder(
      listenable: coach,
      builder: (BuildContext c, Widget? w) => _body(ctx, coach, canStartNew),
    ),
    title: 'Chats',
  );
}

Widget _body(BuildContext ctx, CoachStore coach, bool canStartNew) {
  final List<Widget> rows = <Widget>[];
  for (final Thread t in coach.visibleThreads) {
    rows.add(ThreadCard(
      title: t.title,
      label: t.about == null ? null : 'Program',
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
      const SizedBox(height: 6),
      ShowAllRow(value: coach.showAllChats, onChanged: coach.setShowAllChats),
      const SizedBox(height: 8),
      ...rows,
    ],
  );
}
