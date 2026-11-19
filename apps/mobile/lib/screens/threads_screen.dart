import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../stores/coach_store.dart';
import '../theme.dart';
import '../widgets/choice_sheet.dart';
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
  /// The first look at the list is decided once: no threads means the user lands in a new chat.
  bool _decided = false;

  CoachStore get _coach => widget.deps.coach;

  @override
  void initState() {
    super.initState();
    _coach.addListener(_maybeOpenEmptyChat);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpenEmptyChat());
  }

  @override
  void dispose() {
    _coach.removeListener(_maybeOpenEmptyChat);
    super.dispose();
  }

  /// No threads (and the list loaded fine): open a new empty chat at once.
  /// The chat replaces this screen, so back goes to the screen before, not to an empty list.
  void _maybeOpenEmptyChat() {
    if (_decided || !mounted || _coach.loadingThreads) {
      return;
    }
    _decided = true;
    if (_coach.threads.isNotEmpty || _coach.error != null || !widget.deps.connection.connected) {
      return;
    }
    _coach.startNewChat();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (BuildContext c) => ChatScreen(deps: widget.deps)),
    );
  }

  void _open(String id) {
    widget.deps.coach.openThread(id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => ChatScreen(deps: widget.deps),
      ),
    );
  }

  /// A new chat opens at once, without a name. The title comes after the first message.
  Future<void> _new() async {
    await _coach.startNewChat();
    if (!mounted) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext c) => ChatScreen(deps: widget.deps)),
    );
  }

  Future<void> _delete(Thread t) async {
    final bool ok = await confirmDelete(context, title: 'Delete this chat?', label: 'Delete chat');
    if (ok && mounted) {
      await _coach.deleteThread(t.id);
    }
  }

  Future<void> _rename(Thread t) async {
    final String? title = await showTextSheet(
      context,
      title: 'Rename chat',
      label: 'Title',
      actionLabel: 'Save',
      initialText: t.title,
    );
    if (title != null) {
      await _coach.renameThread(t.id, title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CoachStore coach = widget.deps.coach;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[coach, widget.deps.connection]),
      builder: (BuildContext context, Widget? child) {
        final List<Widget> rows = <Widget>[];
        for (final Thread t in coach.threads) {
          rows.add(ThreadCard(
            title: t.title,
            lastMessage: t.thinking
                ? 'Coach is thinking…'
                : t.failed
                    ? 'The coach could not answer.'
                    : t.lastMessage,
            onTap: () => _open(t.id),
            onRename: () => _rename(t),
            onDelete: () => _delete(t),
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
                      if (!widget.deps.connection.connected) ...<Widget>[
                        const NoteBox(
                          title: 'Offline.',
                          message: 'Chat needs a connection. Threads show when you are back online.',
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (err != null) ...<Widget>[
                        NoteBox(title: 'Chat is not available.', message: err),
                        const SizedBox(height: 18),
                      ],
                      if (coach.loadingThreads && coach.threads.isEmpty)
                        Text('Loading…', style: OG.muted())
                      else if (coach.threads.isEmpty && err == null)
                        const NoteBox(
                          title: 'No chats yet.',
                          message: 'Start one for a topic, like a lift or a plan.',
                        ),
                      ...rows,
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: CtaButton(
                    label: 'New chat',
                    icon: Icons.add,
                    variant: OgVariant.accent,
                    onPressed: widget.deps.connection.connected ? _new : null,
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
