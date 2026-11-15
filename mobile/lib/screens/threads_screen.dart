import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../stores/coach_store.dart';
import '../theme.dart';
import '../widgets/cta_button.dart';
import '../widgets/note_box.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/text_sheet.dart';
import '../widgets/thread_card.dart';
import 'chat_screen.dart';

class ThreadsScreen extends StatefulWidget {
  const ThreadsScreen({super.key, required this.deps});

  final AppDeps deps;

  @override
  State<ThreadsScreen> createState() => _ThreadsScreenState();
}

class _ThreadsScreenState extends State<ThreadsScreen> {
  @override
  void initState() {
    super.initState();
    widget.deps.coach.loadThreads();
  }

  void _open(String id) {
    widget.deps.coach.openThread(id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => ChatScreen(deps: widget.deps),
      ),
    );
  }

  Future<void> _new() async {
    final String? title = await showTextSheet(
      context,
      title: 'New thread',
      label: 'Title',
      hint: 'e.g. Squat progress',
      actionLabel: 'Create',
    );
    if (title == null) {
      return;
    }
    final String t = title.length > 40 ? title.substring(0, 40) : title;
    final Thread? created = await widget.deps.coach.createThread(t);
    if (created != null && mounted) {
      _open(created.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CoachStore coach = widget.deps.coach;
    return ListenableBuilder(
      listenable: coach,
      builder: (BuildContext context, Widget? child) {
        final List<Widget> rows = <Widget>[];
        for (final Thread t in coach.threads) {
          rows.add(ThreadCard(
            title: t.title,
            lastMessage: t.lastMessage,
            onTap: () => _open(t.id),
            onDelete: () => coach.deleteThread(t.id),
          ));
          rows.add(const SizedBox(height: 12));
        }
        final String? err = coach.error;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          OgIconButton(
                            icon: Icons.chevron_left,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text('Coach', style: OG.display(32))),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (err != null) ...<Widget>[
                        NoteBox(title: 'Chat is not available.', message: err),
                        const SizedBox(height: 12),
                        OgButton(
                          onPressed: coach.loadThreads,
                          child: const Text('Try again'),
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (coach.loadingThreads && coach.threads.isEmpty)
                        Text('Loading…', style: OG.muted())
                      else if (coach.threads.isEmpty && err == null)
                        const NoteBox(
                          title: 'No threads yet.',
                          message: 'Start one for a topic, like a lift or a plan.',
                        ),
                      ...rows,
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: CtaButton(
                    label: 'New thread',
                    icon: Icons.add,
                    variant: OgVariant.accent,
                    onPressed: _new,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
