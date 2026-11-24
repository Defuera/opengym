import 'package:flutter/material.dart';

import '../app/deps.dart';
import 'chat_screen.dart';

/// Opens the log chat (ADR-032): the one chat screen in a new thread with the
/// context `screen: "log"`, the composer focused. Nothing is written to the
/// log until the person presses Done on the draft.
Future<void> openLogChat(NavigatorState nav, AppDeps deps) async {
  await deps.coach.openLog();
  await nav.push(MaterialPageRoute<void>(builder: (BuildContext c) => ChatScreen(deps: deps, autofocus: true)));
}
