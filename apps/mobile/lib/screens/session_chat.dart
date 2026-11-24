import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import 'chat_screen.dart';

/// Opens the one chat from the open session (ADR-032). With [exercise] the
/// chat is about that one exercise; without it, about the whole session. The
/// thread is the same each time while the session is open.
Future<void> openSessionChat(BuildContext context, AppDeps deps, Session session, {Exercise? exercise}) async {
  final NavigatorState nav = Navigator.of(context);
  final String focus = (session.focus ?? '').trim();
  await deps.coach.openWithContext(
    context: ChatContext(
      screen: exercise == null ? 'session' : 'exercise',
      openSessionId: session.id,
      exerciseId: exercise?.id,
    ),
    line: exercise == null
        ? 'This session: ${session.type}${focus.isEmpty ? '' : ', $focus'}'
        : 'This exercise: ${exercise.name}',
    hint: 'What do you want to change?',
  );
  await nav.push(MaterialPageRoute<void>(builder: (BuildContext c) => ChatScreen(deps: deps)));
}
