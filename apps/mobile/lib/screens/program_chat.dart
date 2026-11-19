import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import 'chat_screen.dart';

/// Opens the chat about a program: [program] null is a new program. The chat
/// is the one that exists for it, or a new empty one.
Future<void> openProgramChat(BuildContext context, AppDeps deps, {Program? program}) async {
  final NavigatorState nav = Navigator.of(context);
  await deps.coach.openAboutProgram(programId: program?.programId, title: program?.title);
  await nav.push(MaterialPageRoute<void>(builder: (BuildContext c) => ChatScreen(deps: deps)));
}
