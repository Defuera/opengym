import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import 'chat_screen.dart';

/// Opens the one chat from the open session (ADR-032). With [exercise] (the
/// one on screen) the context is that exercise; without it, the session. The
/// thread is the same each time while the session is open.
Future<void> openSessionChat(BuildContext context, AppDeps deps, Session session, {Exercise? exercise}) async {
  final NavigatorState nav = Navigator.of(context);
  final String focus = (session.focus ?? '').trim();
  final String head = '${session.type}${focus.isEmpty ? '' : ', $focus'}';
  await deps.coach.openWithContext(
    context: ChatContext(
      screen: exercise == null ? 'session' : 'exercise',
      openSessionId: session.id,
      exerciseId: exercise?.id,
    ),
    line: exercise == null ? head : '$head \u00b7 ${exercise.name}',
    hint: 'What do you want to change?',
  );
  await nav.push(MaterialPageRoute<void>(builder: (BuildContext c) => ChatScreen(deps: deps)));
}
