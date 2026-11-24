import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import 'chat_screen.dart';

/// Opens the one chat to add a goal, a limit or a note, or to change one the
/// person has (ADR-032, step D). It is a new thread with the context
/// `screen: "goal" | "limit" | "note"`, the composer focused and a short hint.
/// The coach drafts; nothing is written until the person presses Done.
Future<void> _open(
  NavigatorState nav,
  AppDeps deps, {
  required ChatContext context,
  required String line,
  required String hint,
  required String composerHint,
}) async {
  await deps.coach.openPart(context: context, line: line, hint: hint, composerHint: composerHint);
  await nav.push(MaterialPageRoute<void>(builder: (BuildContext c) => ChatScreen(deps: deps, autofocus: true)));
}

/// A new goal, or the goal [change] when given.
Future<void> openGoalChat(NavigatorState nav, AppDeps deps, {Goal? change}) => _open(
      nav,
      deps,
      context: ChatContext(screen: 'goal', goalId: change?.id),
      line: change == null ? 'New goal' : 'Goal · ${change.title}',
      hint: change == null
          ? 'Say what you want to reach. The coach drafts the goal and you press Done.'
          : 'Say what should change. The coach drafts the new goal and you press Done.',
      composerHint: change == null ? 'Bench press 70 kg by spring' : 'What should change?',
    );

/// A new limit ([part] is the body part key from the figure), or the limit [change].
Future<void> openLimitChat(NavigatorState nav, AppDeps deps, {String? part, Limit? change}) => _open(
      nav,
      deps,
      context: ChatContext(screen: 'limit', limitId: change?.id, part: change?.part ?? part),
      line: change != null
          ? 'Limit · ${change.title}'
          : part != null
              ? 'New limit · ${partLabel(part)}'
              : 'New limit',
      hint: change == null
          ? 'Say which body part and what to avoid. The coach drafts the limit and you press Done.'
          : 'Say what should change. The coach drafts the new limit and you press Done.',
      composerHint: change == null ? 'My left knee hurts on deep squats' : 'What should change?',
    );

/// A new note for the coach, or the note [change].
Future<void> openNoteChat(NavigatorState nav, AppDeps deps, {ContextItem? change}) => _open(
      nav,
      deps,
      context: ChatContext(screen: 'note', noteId: change?.id),
      line: change == null ? 'New preference' : 'Preference · ${change.topic}',
      hint: change == null
          ? 'Tell the coach what it should know about you. It drafts a note and you press Done.'
          : 'Say what should change. The coach drafts the new note and you press Done.',
      composerHint: change == null ? 'I always warm up for 10 minutes' : 'What should change?',
    );
