import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../data/upload_item.dart';
import '../stores/coach_store.dart';
import '../theme.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chip_strip.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/composer_bar.dart';
import '../widgets/note_box.dart';
import '../widgets/og_button.dart';
import '../widgets/og_icon_button.dart';
import '../widgets/saved_chips.dart';
import '../widgets/text_sheet.dart';

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

  Future<void> _attachFile() async {
    try {
      final List<UploadItem> files = await widget.deps.pickers.pickFiles();
      for (final UploadItem f in files) {
        _coach.addAttachment(f);
      }
      if (!mounted) {
        return;
      }
      setState(() => _pickError = null);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _pickError = 'Could not open the file picker.');
    }
  }

  Future<void> _attachPhoto() async {
    final String? src = await showChoiceSheet(
      context,
      title: 'Attach a photo',
      choices: const <SheetChoice>[
        SheetChoice(value: 'camera', label: 'Take a photo'),
        SheetChoice(value: 'gallery', label: 'Choose from library'),
      ],
    );
    if (src == null) {
      return;
    }
    try {
      final UploadItem? p =
          await widget.deps.pickers.pickPhoto(camera: src == 'camera');
      if (p != null) {
        _coach.addAttachment(p);
      }
      if (!mounted) {
        return;
      }
      setState(() => _pickError = null);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _pickError = 'Could not open the camera or library.');
    }
  }

  /// A new chat opens at once, without a name.
  Future<void> _newThread() => _coach.startNewChat();

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

  List<Widget> _items(CoachStore c) {
    final List<Widget> items = <Widget>[];
    for (final Message m in c.messages) {
      final int n = m.fileIds.length;
      items.add(ChatBubble(
        text: m.text,
        mine: m.mine,
        sources: m.sources,
        attachments: n == 0 ? const <String>[] : <String>['$n file${n == 1 ? '' : 's'}'],
      ));
      items.add(const SizedBox(height: 12));
    }
    if (c.saved.isNotEmpty) {
      items.add(SavedChips(labels: c.saved));
      items.add(const SizedBox(height: 12));
    }
    if (c.thinking) {
      items.add(const ChatBubble(text: 'Thinking…', mine: false));
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
    if (c.messages.isEmpty && !c.loadingMessages && !c.sending) {
      items.add(const NoteBox(
        title: 'Say anything about your training.',
        message: 'Questions, goals, or what you did today. Statements are fine.',
      ));
    }
    return items.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_coach, widget.deps.connection]),
      builder: (BuildContext context, Widget? child) {
        final CoachStore c = _coach;
        final int sel = c.threads.indexWhere((Thread t) => t.id == c.currentId);
        // A send problem is shown with its retry action, not twice.
        final String err = c.retryReason != null ? (_pickError ?? '') : (c.error ?? _pickError ?? '');
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: <Widget>[
                      OgIconButton(
                        icon: Icons.chevron_left,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          key: const ValueKey<String>('chat-title'),
                          behavior: HitTestBehavior.opaque,
                          onTap: c.currentThread == null ? null : () => _rename(c.currentThread!),
                          child: Text(
                            c.currentThread?.title ?? (c.isDraft ? 'New chat' : 'Coach'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OG.display(32),
                          ),
                        ),
                      ),
                      if (c.currentThread != null)
                        OgIconButton(
                          key: const ValueKey<String>('chat-rename'),
                          icon: Icons.edit_outlined,
                          onPressed: () => _rename(c.currentThread!),
                        ),
                    ],
                  ),
                ),
                ChipStrip(
                  labels: c.threads.map((Thread t) => t.title).toList(),
                  selectedIndex: sel,
                  onSelect: (int i) => c.openThread(c.threads[i].id),
                  onAdd: _newThread,
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
                    child: ListView(
                      reverse: true,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
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
                  attachmentNames: c.attachments.map((UploadItem u) => u.name).toList(),
                  onRemoveAttachment: c.removeAttachment,
                  onAttachFile: _attachFile,
                  onAttachPhoto: _attachPhoto,
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
