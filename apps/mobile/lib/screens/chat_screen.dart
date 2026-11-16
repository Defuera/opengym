import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../data/api/open_gym_api.dart';
import '../stores/coach_store.dart';
import '../theme.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chip_strip.dart';
import '../widgets/choice_sheet.dart';
import '../widgets/composer_bar.dart';
import '../widgets/note_box.dart';
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
  String? _pickError;

  CoachStore get _coach => widget.deps.coach;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final bool ok = await _coach.send(_text.text);
    if (ok) {
      _text.clear();
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

  Future<void> _newThread() async {
    final String? title = await showTextSheet(
      context,
      title: 'New thread',
      label: 'Title',
      actionLabel: 'Create',
    );
    if (title == null) {
      return;
    }
    final Thread? t =
        await _coach.createThread(title.length > 40 ? title.substring(0, 40) : title);
    if (t != null) {
      _coach.openThread(t.id);
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
    if (c.saved.isNotEmpty && !c.sending) {
      items.add(SavedChips(labels: c.saved));
      items.add(const SizedBox(height: 12));
    }
    if (c.sending) {
      items.add(const ChatBubble(text: 'Thinking…', mine: false));
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
      listenable: _coach,
      builder: (BuildContext context, Widget? child) {
        final CoachStore c = _coach;
        final int sel = c.threads.indexWhere((Thread t) => t.id == c.currentId);
        final String err = c.error ?? _pickError ?? '';
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
                        child: Text(
                          c.currentThread?.title ?? 'Coach',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OG.display(32),
                        ),
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
                  child: ListView(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    children: _items(c),
                  ),
                ),
                ComposerBar(
                  controller: _text,
                  sending: c.sending,
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
