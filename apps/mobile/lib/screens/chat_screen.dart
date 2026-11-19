import 'package:flutter/material.dart';

import '../app/deps.dart';
import '../models.dart';
import '../data/upload_item.dart';
import '../stores/coach_store.dart';
import '../stores/voice_controller.dart';
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
import 'chat_proposal.dart';
import 'chat_threads_sheet.dart';
import 'program_screen.dart';

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
  final Set<String> _deciding = <String>{};
  late final VoiceController _voice;

  CoachStore get _coach => widget.deps.coach;

  @override
  void initState() {
    super.initState();
    _voice = VoiceController(recorder: widget.deps.voice, onRecorded: _sendVoice);
  }

  Future<void> _sendVoice(UploadItem audio) async {
    await _coach.sendVoice(audio);
  }

  @override
  void dispose() {
    _voice.dispose();
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

  Future<void> _agree(Proposal p) async {
    setState(() => _deciding.add(p.proposalId));
    final String? programId = await _coach.acceptProposal(p.proposalId);
    if (!mounted) {
      return;
    }
    setState(() => _deciding.remove(p.proposalId));
    if (programId != null) {
      _openProgram(programId);
    }
  }

  Future<void> _cancel(Proposal p) async {
    setState(() => _deciding.add(p.proposalId));
    await _coach.declineProposal(p.proposalId);
    if (mounted) {
      setState(() => _deciding.remove(p.proposalId));
    }
  }

  void _openProgram(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext c) => ProgramScreen(deps: widget.deps, programId: id)),
    );
  }

  bool _showHint(CoachStore c) => c.messages.isEmpty && !c.loadingMessages && !c.sending && c.retryReason == null;

  List<Widget> _items(CoachStore c) {
    final List<Widget> items = <Widget>[];
    for (final Message m in c.messages) {
      items.add(ChatBubble(
        text: m.text,
        mine: m.mine,
        sources: m.sources,
        voice: m.voice,
        voiceFailedText:
            c.isUnsentVoice(m.id) ? 'Could not send the recording.' : 'Could not read the recording.',
        onRetryVoice: c.sending ? null : () => c.retryVoice(m.id),
        copyable: m.voice != 'pending' && m.voice != 'failed',
        media: <Widget>[
          // The audio itself is never shown, only its text.
          for (final String id in (m.voice == null ? m.fileIds : const <String>[]))
            ChatFileThumb(key: ValueKey<String>('file-$id'), coach: c, fileId: id),
        ],
      ));
      items.add(const SizedBox(height: 12));
      final String? pid = m.proposalId;
      if (pid != null && !m.mine) {
        final Proposal? p = c.proposalById(pid);
        items.add(ChatProposal(
          proposal: p,
          live: pid == c.liveProposalId,
          busy: _deciding.contains(pid),
          programId: c.currentAbout?.id,
          onOpenProgram: _openProgram,
          onAgree: () => p == null ? null : _agree(p),
          onCancel: () => p == null ? null : _cancel(p),
        ));
        if (p != null) {
          items.add(const SizedBox(height: 12));
        }
      }
    }
    if (c.saved.isNotEmpty) {
      items.add(SavedChips(labels: c.saved));
      items.add(const SizedBox(height: 12));
    }
    final List<Message> all = c.messages;
    final bool listening = all.isNotEmpty && all.last.voice == 'pending';
    if (c.thinking && !listening) {
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
      listenable: Listenable.merge(<Listenable>[_coach, widget.deps.connection, _voice]),
      builder: (BuildContext context, Widget? child) {
        final CoachStore c = _coach;
        final ThreadAbout? about = c.currentAbout;
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
                                about == null
                                    ? 'Ask anything about your training, or say what you did.'
                                    : about.id == null
                                        ? 'Tell the coach what program you want, or paste one. The coach writes it here for you to agree.'
                                        : 'Ask about this program, or say what should change. The coach shows the change here for you to agree.',
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
                  hint: about == null
                      ? 'Message'
                      : about.id == null
                          ? 'Paste a program, or say what you want'
                          : 'Ask, or say what should change',
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
                  onMic: _voice.start,
                  recording: _voice.recording,
                  recordSeconds: _voice.seconds,
                  onCancelRecording: _voice.cancel,
                  onStopRecording: _voice.stopAndSend,
                  voiceNote: _voice.note,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
