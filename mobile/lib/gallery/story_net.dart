import 'package:flutter/material.dart';

import '../widgets/attachment_chip.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/consistency_row.dart';
import '../widgets/goal_progress_card.dart';
import '../widgets/goal_row.dart';
import '../widgets/import_job_card.dart';
import '../widgets/nav_bar.dart';
import '../widgets/note_card.dart';
import '../widgets/og_button.dart';
import '../widgets/preparing_card.dart';
import '../widgets/progress_bar.dart';
import '../widgets/review_card.dart';
import '../widgets/saved_chips.dart';
import '../widgets/status_line.dart';
import '../widgets/text_sheet.dart';
import '../widgets/thread_card.dart';
import '../widgets/trend_card.dart';

/// Stories for the widgets that show server data. Values are neutral samples.

void _noop() {}

const SizedBox _gap = SizedBox(height: 12);

Widget progressStory(BuildContext context) {
  return const Column(
    children: <Widget>[
      ProgressBar(fraction: 0.65),
      _gap,
      ProgressBar(fraction: 0),
      _gap,
      ProgressBar(fraction: null),
    ],
  );
}

Widget statusStory(BuildContext context) {
  return const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      StatusLine(text: 'Connected', connected: true),
      _gap,
      StatusLine(text: 'Offline: saved on this phone', connected: false),
    ],
  );
}

Widget goalCardStory(BuildContext context) {
  return const Column(
    children: <Widget>[
      GoalProgressCard(
        title: 'Bench press',
        current: '50 kg',
        target: '80 kg',
        fraction: 0.62,
      ),
      _gap,
      GoalProgressCard(
        title: 'Train three times a week',
        current: '1 this week',
        target: '3',
        fraction: null,
      ),
    ],
  );
}

Widget trendStory(BuildContext context) {
  return const Column(
    children: <Widget>[
      TrendCard(
        title: 'Bench press top set',
        unit: 'kg',
        values: <double>[40, 45, 45, 50, 52.5, 55],
      ),
      _gap,
      TrendCard(title: 'No data', unit: 'kg', values: <double>[]),
    ],
  );
}

Widget consistencyStory(BuildContext context) {
  final List<bool> week = <bool>[true, false, true, false, true, true, false];
  final List<bool> month = <bool>[
    for (int i = 0; i < 30; i++) i % 3 != 1,
  ];
  return Column(
    children: <Widget>[
      ConsistencyRow(title: 'Active days', days: week),
      _gap,
      ConsistencyRow(title: 'Active days', days: month),
    ],
  );
}

Widget noteCardStory(BuildContext context) {
  return const NoteCard(text: 'Sample note from the dashboard.');
}

Widget reviewStory(BuildContext context) {
  return ReviewCard(
    summary: 'Sample summary of the last session.',
    changes: const <String>['Sample change one', 'Sample change two'],
    onDismiss: _noop,
  );
}

Widget chatStory(BuildContext context) {
  return const Column(
    children: <Widget>[
      ChatBubble(text: 'Sample message from you.', mine: true),
      _gap,
      ChatBubble(
        text: 'Sample reply from the coach.',
        mine: false,
        sources: <String>['gym log', 'goals'],
      ),
      _gap,
      SavedChips(labels: <String>['Goal: sample goal', 'Sample context note']),
    ],
  );
}

Widget attachmentStory(BuildContext context) {
  return const Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      AttachmentChip(name: 'history.csv', onRemove: _noop),
      AttachmentChip(name: 'a-very-long-file-name-for-the-chip.jpg', onRemove: _noop),
    ],
  );
}

Widget threadCardStory(BuildContext context) {
  return const Column(
    children: <Widget>[
      ThreadCard(title: 'Squat', lastMessage: 'Sample last message.', onTap: _noop),
      _gap,
      ThreadCard(title: 'New topic', onTap: _noop, onDelete: _noop),
    ],
  );
}

Widget navBarStory(BuildContext context) {
  return const NavBar(onHome: _noop, onPlus: _noop, onChat: _noop);
}

Widget goalRowStory(BuildContext context) {
  return const Column(
    children: <Widget>[
      GoalRow(
        title: 'Bench press 80 kg',
        detail: 'Strength · Bench press · 80 kg',
        done: false,
        onToggleDone: _noop,
        onDelete: _noop,
      ),
      _gap,
      GoalRow(
        title: 'Three sessions a week',
        detail: 'Consistency · 3 / week',
        done: true,
        onToggleDone: _noop,
        onDelete: _noop,
      ),
    ],
  );
}

Widget importStory(BuildContext context) {
  return const Column(
    children: <Widget>[
      ImportJobCard(
        title: 'This import',
        processed: 1,
        total: 3,
        running: true,
        summary: '',
      ),
      _gap,
      ImportJobCard(
        title: 'Import · yesterday',
        processed: 3,
        total: 3,
        running: false,
        summary: '4 sessions, 1 goals, 0 context notes saved',
        notes: <String>['Sample note about a file.'],
        onUndo: _noop,
      ),
    ],
  );
}

Widget preparingStory(BuildContext context) {
  return const PreparingCard(
    title: 'Preparing your session…',
    message: 'Looking at your log and goals.',
    actionLabel: 'Use my last session',
    onAction: _noop,
  );
}

Widget textSheetStory(BuildContext context) {
  return OgButton(
    onPressed: () {
      showTextSheet(
        context,
        title: 'New thread',
        label: 'Title',
        actionLabel: 'Create',
      );
    },
    child: const Text('Open text sheet'),
  );
}
