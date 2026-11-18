import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../data/upload_item.dart';
import '../stores/coach_store.dart';
import '../theme.dart';
import '../widgets/attach_sheet.dart';
import '../widgets/attachment_strip.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/composer_bar.dart';
import '../widgets/note_box.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/saved_chips.dart';
import '../widgets/text_sheet.dart';
import 'chat_file_thumb.dart';
import 'chat_threads_sheet.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.deps});

  final AppDeps deps;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  String? _pickError;

  CoachStore get _coach => widget.deps.coach;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _text.text;
    _text.clear();
    final bool accepted = await _coach.send(text);
    if (!accepted) {
      _text.text = text; // nothing was sent: keep what the user typed
    }
    if (mounted) {
      _focus.requestFocus(); // sending keeps the keyboard open
    }
  }

  Future<void> _attach() async {
    final AttachChoice? choice = await showAttachSheet(context);
    if (choice == null) {
      return;
    }
    try {
      if (choice == AttachChoice.file) {
        for (final UploadItem f in await widget.deps.pickers.pickFiles()) {
          _coach.addAttachment(f);
        }
      } else {
        final UploadItem? p =
            await widget.deps.pickers.pickPhoto(camera: choice == AttachChoice.camera);
        if (p != null) {
          _coach.addAttachment(p);
        }
      }
      if (!mounted) {
        return;
      }
      setState(() => _pickError = null);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _pickError = choice == AttachChoice.file
          ? 'Could not open the file picker.'
          : 'Could not open the camera or library.');
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

  bool _showHint(CoachStore c) => c.messages.isEmpty && !c.loadingMessages && !c.sending && c.retryReason == null;

  List<Widget> _items(CoachStore c) {
    final List<Widget> items = <Widget>[];
    for (final Message m in c.messages) {
      items.add(ChatBubble(
        text: m.text,
        mine: m.mine,
        sources: m.sources,
        media: <Widget>[
          for (final String id in m.fileIds)
            ChatFileThumb(key: ValueKey<String>('file-$id'), coach: c, fileId: id),
        ],
      ));
      items.add(const SizedBox(height: 12));
    }
    if (c.saved.isNotEmpty) {
      items.add(SavedChips(labels: c.saved));
      items.add(const SizedBox(height: 12));
    }
    if (c.thinking) {
      items.add(const ChatBubble(text: 'Thinking…', mine: false, copyable: false));
      items.add(const SizedBox(height: 12));
    }
    final String? why = c.retryReason;
    if (why != null) {
      items.add(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          NoteBox(title: 'That did not work.', message: why),
          const SizedBox(height: 8),
          OgButton(
            onPressed: c.sending ? null : c.retry,
            child: const Text('Try again'),
          ),
        ],
      ));
      items.add(const SizedBox(height: 12));
    }
    return items.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_coach, widget.deps.connection]),
      builder: (BuildContext context, Widget? child) {
        final CoachStore c = _coach;
        // A send problem is shown with its retry action, not twice.
        final String err = c.retryReason != null ? (_pickError ?? '') : (c.error ?? _pickError ?? '');
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                GestureDetector(
                  // A tap on the empty part of the header closes the keyboard too.
                  behavior: HitTestBehavior.translucent,
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                  child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Row(
                    children: <Widget>[
                      OgIconButton(
                        icon: Icons.chevron_left,
                        size: 44,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            key: const ValueKey<String>('chat-title'),
                            behavior: HitTestBehavior.opaque,
                            onTap: c.currentThread == null ? null : () => _rename(c.currentThread!),
                            child: Text(
                              c.currentThread?.title ?? (c.isDraft ? (c.draftTitle ?? 'New chat') : 'Coach'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OG.display(24),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OgIconButton(
                        key: const ValueKey<String>('chat-threads'),
                        icon: Icons.forum_outlined,
                        size: 44,
                        onPressed: () => showChatThreadsSheet(
                          context,
                          coach: c,
                          canStartNew: widget.deps.connection.connected,
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
                if (err.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Text(err, style: OG.body(size: 15, weight: FontWeight.w600)),
                  ),
                Expanded(
                  // A tap on the messages closes the keyboard; so does a drag.
                  child: GestureDetector(
                    key: const ValueKey<String>('chat-messages'),
                    behavior: HitTestBehavior.translucent,
                    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                    child: _showHint(c)
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 40),
                              child: Text(
                                'Ask anything about your training, or say what you did.',
                                key: const ValueKey<String>('chat-hint'),
                                textAlign: TextAlign.center,
                                style: OG.muted(size: 16),
                              ),
                            ),
                          )
                        : ListView(
                            reverse: true,
                            physics: const AlwaysScrollableScrollPhysics(),
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            children: _items(c),
                          ),
                  ),
                ),
                ComposerBar(
                  controller: _text,
                  focusNode: _focus,
                  sending: c.sending,
                  offlineNote: widget.deps.connection.connected
                      ? null
                      : 'Offline. Chat needs a connection to send.',
                  attachments: <StripItem>[
                    for (final UploadItem u in c.attachments)
                      StripItem(name: u.name, image: imageForUpload(u)),
                  ],
                  onRemoveAttachment: c.removeAttachment,
                  onAttach: _attach,
                  onSend: _send,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
