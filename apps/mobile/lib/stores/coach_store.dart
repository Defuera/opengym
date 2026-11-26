import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../data/outbox.dart';
import '../data/outbox_ops.dart';
import '../data/transcript_result.dart';
import '../data/upload_item.dart';
import '../models.dart';
import '../planner.dart';

const String chatOfflineMessage = 'Chat needs a connection. Nothing was sent.';

/// The hint of an empty log chat.
const String logComposerHint = 'What did you do or eat?';
const String logChatHint = 'Write it, or add a photo or a file. I will work out what it is.';

/// The most files one chat message holds. The same number as the server (`fileIds` max 10 in `model/schema/thread.ts`).
const int messageMaxFiles = 10;

class _Attachment {
  _Attachment(this.item, [String? id]) : fileId = id ?? newId();

  final UploadItem item;
  final String fileId;
  bool uploaded = false;
}

/// A message the user sent that the server copy has not replaced yet. It keeps
/// its id, so a retry sends the same id and the server never stores it twice.
class _Outgoing {
  _Outgoing({
    required this.messageId,
    required this.threadId,
    required this.text,
    required this.files,
    this.context,
    this.answer,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  final String messageId;
  final String threadId;
  final String text;
  final List<_Attachment> files;
  final int createdAt;

  /// What was open when the person sent it.
  final ChatContext? context;

  /// Set when the text is a tap on a quick answer.
  final ChatAnswer? answer;

  Message toMessage() => Message(
        id: messageId,
        threadId: threadId,
        role: 'user',
        text: text,
        createdAt: createdAt,
        fileIds: <String>[for (final _Attachment f in files) f.fileId],
      );
}

/// Coach chat on live Convex subscriptions: the thread list, the messages of
/// the open thread, and the goals and notes the coach saved. The user message
/// shows at once; the server copy replaces it (matched by message id). The
/// answer is never returned by a call: it arrives through the subscription,
/// and the thread status says `thinking`, `idle` or `failed`.
///
/// Typing and sending never wait for the connection (ADR-037). A message
/// shows at once, is saved in the outbox on disk, and goes out when it can:
/// "Sending…" while it goes, "Not sent" with "Try again" when it did not. The
/// text and the files are kept. Reading the thread, voice and the proposal
/// buttons still need a connection.
class CoachStore extends ChangeNotifier {
  CoachStore({required ConvexClient client, required bool Function() isConnected, Outbox? outbox})
      : _client = client,
        _isConnected = isConnected,
        _outbox = outbox ??
            Outbox(
              repo: InMemoryOutboxRepository(),
              client: client,
              isConnected: isConnected,
              retryAfter: const Duration(hours: 1),
            ) {
    _outbox.addListener(_onOutbox);
    _onOutbox(notify: false);
  }

  final ConvexClient _client;
  final bool Function() _isConnected;
  final Outbox _outbox;

  List<Thread> threads = <Thread>[];
  String? currentId;

  /// The open chat is new and not on the server yet. It is created with the
  /// first message, so backing out leaves no empty thread behind.
  bool isDraft = false;

  /// Set on a draft chat about a place: the place id and the thread title.
  String? draftPlaceId;
  String? draftTitle;

  /// Set on a draft chat about a program (the server names the thread).
  ThreadAbout? draftAbout;

  /// What the open chat was opened from (ADR-032). Null: a plain chat.
  ChatContext? chatContext;

  /// The small line at the top of a chat opened with a context, and the hint
  /// shown while it is empty. Null on a plain chat.
  String? contextLine;
  String? contextHint;

  /// The hint text inside the composer for this chat (null: the default one).
  String? composerHint;

  /// The chat thread this run made for each open session, until the server
  /// list shows it (see [sessionThreadId]).
  final Map<String, String> _sessionThreads = <String, String>{};

  /// The chat list shows chats that are about something (a program) too.
  /// Kept for the run of the app; off at first.
  bool showAllChats = false;

  /// The proposals of the open chat, oldest first, as the server has them.
  List<Proposal> proposals = <Proposal>[];
  bool loadingThreads = true;
  bool loadingMessages = false;

  /// A message is going out right now. Never blocks typing or sending.
  bool get sending => _outbox.sendingChat;

  /// Readable problem for the screen, else null.
  String? error;

  List<Message> _server = <Message>[];
  List<Goal> _goals = <Goal>[];
  List<ContextItem> _context = <ContextItem>[];
  final List<_Outgoing> _outgoing = <_Outgoing>[];
  final List<_Attachment> _pending = <_Attachment>[];

  StreamSubscription<List<Thread>>? _threadSub;
  StreamSubscription<List<Message>>? _msgSub;
  StreamSubscription<List<Proposal>>? _propSub;
  final Completer<void> _threadsLoaded = Completer<void>();
  StreamSubscription<List<Goal>>? _goalSub;
  StreamSubscription<List<ContextItem>>? _ctxSub;

  bool get connected => _isConnected();

  List<UploadItem> get attachments => <UploadItem>[for (final _Attachment p in _pending) p.item];

  final Map<String, Future<FileLink?>> _links = <String, Future<FileLink?>>{};

  /// Meta and address of a sent file, looked up once. Null when it is not found.
  Future<FileLink?> fileLink(String fileId) {
    return _links.putIfAbsent(fileId, () async {
      try {
        return await _client.fileLink(fileId);
      } catch (_) {
        _links.remove(fileId); // try again next time
        return null;
      }
    });
  }

  final Map<String, UploadItem> _sentFiles = <String, UploadItem>{};

  /// The local file behind a message this device sent, else null.
  UploadItem? localFile(String fileId) => _sentFiles[fileId];

  /// What the open chat is about: its thread, or the draft before it exists.
  ThreadAbout? get currentAbout => currentThread?.about ?? draftAbout;

  /// The chats the list shows: those that are about something only on request.
  /// A new chat whose first message is not on the server yet is listed too.
  List<Thread> get visibleThreads {
    final List<Thread> all = <Thread>[..._unsentThreads, ...threads];
    return showAllChats ? all : <Thread>[for (final Thread t in all) if (t.about == null) t];
  }

  List<Thread> get _unsentThreads {
    final Set<String> known = <String>{for (final Thread t in threads) t.id};
    final List<Thread> out = <Thread>[];
    for (final QueuedChat q in _outbox.chats.reversed) {
      if (q.newThread && !known.contains(q.threadId) && !out.any((Thread t) => t.id == q.threadId)) {
        out.add(Thread(
          id: q.threadId,
          title: q.threadTitle ?? (q.text.length > 40 ? '${q.text.substring(0, 40)}…' : q.text),
          createdAt: q.createdAt,
          updatedAt: q.createdAt,
          about: q.threadAbout,
        ));
      }
    }
    return out;
  }

  void setShowAllChats(bool v) {
    showAllChats = v;
    notifyListeners();
  }

  /// The one proposal of the open chat that has live buttons: the newest
  /// `ready` one. Null when there is none.
  String? get liveProposalId {
    for (final Proposal p in proposals.reversed) {
      if (p.ready) {
        return p.proposalId;
      }
    }
    return null;
  }

  Proposal? proposalById(String? id) {
    if (id == null) {
      return null;
    }
    for (final Proposal p in proposals) {
      if (p.proposalId == id) {
        return p;
      }
    }
    return null;
  }

  Thread? get currentThread {
    for (final Thread t in threads) {
      if (t.id == currentId) {
        return t;
      }
    }
    return null;
  }

  /// Server messages plus the ones not yet echoed, oldest first.
  List<Message> get messages {
    final Set<String> known = <String>{for (final Message m in _server) m.id};
    return <Message>[
      ..._server,
      for (final _Outgoing o in _outgoing)
        if (o.threadId == currentId && !known.contains(o.messageId)) o.toMessage(),
    ];
  }

  /// The coach is working on a reply.
  bool get thinking => currentThread?.thinking ?? false;

  /// Where a message of this device stands: sending, not sent, or null (it is
  /// on the server, or it is not ours).
  ChatDelivery? delivery(String messageId) => _outbox.chatDelivery(messageId);

  /// "Try again" on a message that was not sent. Same message id.
  Future<void> retryMessage(String messageId) {
    error = null;
    notifyListeners();
    return _outbox.retryChat(messageId);
  }

  /// Short problem text next to a retry action, else null: the coach job failed.
  /// An unsent message has its own "Not sent" on the bubble.
  String? get retryReason {
    final Thread? t = currentThread;
    if (t != null && t.failed) {
      return (t.error ?? '').isEmpty ? 'The coach could not answer.' : t.error;
    }
    return null;
  }

  /// Goals and notes the coach saved from the last answer: items tagged with
  /// this thread and made after the last user message.
  List<String> get saved {
    final Thread? t = currentThread;
    if (t == null || t.thinking || _server.isEmpty || _server.last.mine) {
      return const <String>[];
    }
    int since = 0;
    for (final Message m in _server.reversed) {
      if (m.mine) {
        since = m.createdAt;
        break;
      }
    }
    return <String>[
      for (final Goal g in _goals)
        if (g.threadId == t.id && g.createdAt >= since) 'Goal: ${g.title}',
      for (final ContextItem c in _context)
        if (c.threadId == t.id && c.createdAt >= since) c.text,
    ];
  }

  /// Open the live thread list (once). Goals and notes are read for the
  /// "saved" chips.
  void start() {
    _threadSub ??= _client.watchThreads().listen(
      (List<Thread> list) {
        threads = list;
        loadingThreads = false;
        if (!_threadsLoaded.isCompleted) {
          _threadsLoaded.complete();
        }
        notifyListeners();
      },
      onError: (Object e) {
        loadingThreads = false;
        if (!_threadsLoaded.isCompleted) {
          _threadsLoaded.complete();
        }
        error = e is ConvexCallException ? e.message : 'Could not load threads.';
        notifyListeners();
      },
    );
    _goalSub ??= _client.watchGoals().listen((List<Goal> g) {
      _goals = g;
      notifyListeners();
    }, onError: (Object _) {});
    _ctxSub ??= _client.watchContext().listen((List<ContextItem> c) {
      _context = c;
      notifyListeners();
    }, onError: (Object _) {});
  }

  /// Opens an empty new chat at once, with a client-made id. Nothing is sent to
  /// the server until the first message, so there is no name prompt and no
  /// empty thread left behind.
  ///
  /// With [placeId] the chat is about that place: the thread is made with the
  /// place and the [title] (for example "About Home").
  Future<void> startNewChat({String? placeId, String? title, ThreadAbout? about}) async {
    await _msgSub?.cancel();
    _msgSub = null;
    await _closeProposals();
    _clearContext();
    currentId = newId();
    isDraft = true;
    draftPlaceId = placeId;
    draftAbout = about;
    draftTitle = (placeId == null && about == null) ? null : title;
    _server = <Message>[];
    _pending.clear();
    loadingMessages = false;
    error = null;
    notifyListeners();
  }

  /// The thread of an open session. The server fact first: the newest thread
  /// whose `openSessionId` is [sessionId] (it survives an app restart). Else
  /// the thread made in this run that the list does not show yet.
  String? sessionThreadId(String sessionId) {
    for (final Thread t in threads) {
      if (t.openSessionId == sessionId) {
        return t.id;
      }
    }
    return _sessionThreads[sessionId];
  }

  /// Opens the one chat with a [context]. From an open session it is the
  /// thread of that session (a new one the first time), so the person comes
  /// back to the same talk while the session is open.
  Future<void> openWithContext({
    required ChatContext context,
    required String line,
    required String hint,
  }) async {
    final String? sid = context.openSessionId;
    final String? known = sid == null ? null : sessionThreadId(sid);
    if (known != null && threads.any((Thread t) => t.id == known)) {
      await openThread(known);
    } else if (known != null && currentId == known && isDraft) {
      // The draft is still open and nothing was sent: keep it.
    } else {
      await startNewChat();
      if (sid != null) {
        _sessionThreads[sid] = currentId!;
      }
    }
    chatContext = context;
    contextLine = line;
    contextHint = hint;
    notifyListeners();
  }

  /// Opens the one chat for a goal, a limit or a note (ADR-032, step D): always a
  /// new thread, with the context of the thing, a line about it and the hints.
  /// The coach drafts; nothing is written until the person presses Done.
  Future<void> openPart({
    required ChatContext context,
    required String line,
    required String hint,
    required String composerHint,
  }) async {
    await startNewChat();
    chatContext = context;
    contextLine = line;
    contextHint = hint;
    this.composerHint = composerHint;
    notifyListeners();
  }

  /// Opens the log chat (ADR-032): always a new thread, with the context
  /// `screen: "log"`. The thread is made with the first message.
  Future<void> openLog() async {
    await startNewChat();
    _setLogContext();
    notifyListeners();
  }

  void _setLogContext() {
    chatContext = const ChatContext(screen: 'log');
    contextLine = 'New log';
    contextHint = logChatHint;
    composerHint = logComposerHint;
  }

  bool get isLogChat => chatContext?.screen == 'log';

  /// The open log chat holds a draft the person pressed Done on.
  bool get logDone => isLogChat && _server.any((Message m) => m.entryId != null || (m.logDraft?.applied ?? false));

  /// The context a message of the open chat carries.
  ChatContext get _sendContext {
    final ChatContext? c = chatContext;
    if (c != null) {
      return c;
    }
    final ThreadAbout? a = currentAbout;
    if (a != null && a.isProgram) {
      return ChatContext(screen: 'program', programId: a.id);
    }
    return const ChatContext(screen: 'chat');
  }

  void _clearContext() {
    chatContext = null;
    contextLine = null;
    contextHint = null;
    composerHint = null;
  }

  /// Opens the chat about a program. [programId] null: a new program. It
  /// reuses the thread that is about it (one per program; one without an id
  /// for a new program, which has no agreed proposal yet), else it opens an
  /// empty draft. [title] is only what the header shows on a draft.
  Future<void> openAboutProgram({String? programId, String? title}) async {
    if (!_threadsLoaded.isCompleted) {
      await _threadsLoaded.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    }
    for (final Thread t in threads) {
      final ThreadAbout? a = t.about;
      if (a != null && a.isProgram && a.id == programId) {
        await openThread(t.id);
        _setProgramContext(programId);
        notifyListeners();
        return;
      }
    }
    await startNewChat(about: ThreadAbout(id: programId), title: title ?? 'New program');
    _setProgramContext(programId);
    notifyListeners();
  }

  /// The context of the program chat (ADR-032, step E): the same chat as every
  /// other, with the screen `program`, a hint and a composer hint.
  void _setProgramContext(String? programId) {
    chatContext = ChatContext(screen: 'program', programId: programId);
    contextLine = null; // the title of the chat is the program
    contextHint = programId == null
        ? 'Tell the coach what program you want, or paste one. The coach writes it here for you to agree.'
        : 'Ask about this program, or say what should change. The coach shows the change here for you to agree.';
    composerHint = programId == null ? 'Paste a program, or say what you want' : 'Ask, or say what should change';
  }

  /// Creates a thread and returns its id. The list updates through the
  /// subscription. No title: the backend names it after the first message.
  Future<String?> createThread([String? title]) async {
    if (!connected) {
      error = chatOfflineMessage;
      notifyListeners();
      return null;
    }
    final String id = newId();
    try {
      await _client.createThread(threadId: id, title: title);
      error = null;
      notifyListeners();
      return id;
    } on ConvexCallException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not create the thread.';
    }
    notifyListeners();
    return null;
  }

  /// The user names a thread. The backend never replaces that title.
  /// Returns false (with [error] set) when it did not go through.
  Future<bool> renameThread(String id, String title) async {
    final String t = title.trim();
    if (t.isEmpty) {
      return false;
    }
    if (!connected) {
      error = chatOfflineMessage;
      notifyListeners();
      return false;
    }
    try {
      await _client.renameThread(threadId: id, title: t.length > 60 ? t.substring(0, 60) : t);
      error = null;
      notifyListeners();
      return true;
    } on ConvexCallException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not rename the thread.';
    }
    notifyListeners();
    return false;
  }

  Future<void> deleteThread(String id) async {
    if (!connected) {
      error = chatOfflineMessage;
      notifyListeners();
      return;
    }
    try {
      await _client.removeThread(id);
      if (currentId == id) {
        await closeThread();
      }
      _outgoing.removeWhere((_Outgoing o) => o.threadId == id);
      await _outbox.dropChatsOf(id);
      error = null;
    } on ConvexCallException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not delete the thread.';
    }
    notifyListeners();
  }

  /// Subscribe to one thread's messages.
  Future<void> openThread(String id) async {
    await _msgSub?.cancel();
    await _closeProposals();
    _clearContext();
    currentId = id;
    isDraft = false;
    draftPlaceId = null;
    draftAbout = null;
    draftTitle = null;
    _server = <Message>[];
    _pending.clear();
    loadingMessages = true;
    error = null;
    notifyListeners();
    _subscribeMessages(id);
    _subscribeProposals(id); // a program proposal can come from any chat (ADR-032, step E)
    final ThreadAbout? about = currentThread?.about;
    if (about != null && about.isProgram) {
      _setProgramContext(about.id);
    }
  }

  void _subscribeMessages(String id) {
    _msgSub = _client.watchMessages(id).listen(
      (List<Message> list) {
        if (currentId != id) {
          return;
        }
        _server = list;
        loadingMessages = false;
        final Set<String> known = <String>{for (final Message m in list) m.id};
        _outgoing.removeWhere((_Outgoing o) => known.contains(o.messageId));
        notifyListeners();
      },
      onError: (Object e) {
        loadingMessages = false;
        error = e is ConvexCallException ? e.message : 'Could not load messages.';
        notifyListeners();
      },
    );
  }

  void _subscribeProposals(String threadId) {
    _propSub = _client.watchThreadProposals(threadId).listen(
      (List<Proposal> list) {
        if (currentId != threadId) {
          return;
        }
        proposals = list;
        notifyListeners();
      },
      onError: (Object _) {},
    );
  }

  Future<void> _closeProposals() async {
    await _propSub?.cancel();
    _propSub = null;
    proposals = <Proposal>[];
  }

  /// The person agrees with a proposal of this chat. Returns the program id,
  /// or null with [error] set.
  Future<String?> acceptProposal(String proposalId) async {
    if (!connected) {
      error = chatOfflineMessage;
      notifyListeners();
      return null;
    }
    try {
      final String id = await _client.acceptProposal(proposalId);
      error = null;
      notifyListeners();
      return id;
    } on ConvexCallException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not save the program. Try again.';
    }
    notifyListeners();
    return null;
  }

  /// The person cancels a proposal of this chat.
  Future<bool> declineProposal(String proposalId) async {
    if (!connected) {
      error = chatOfflineMessage;
      notifyListeners();
      return false;
    }
    try {
      await _client.declineProposal(proposalId);
      error = null;
      notifyListeners();
      return true;
    } on ConvexCallException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not cancel it. Try again.';
    }
    notifyListeners();
    return false;
  }

  Future<void> closeThread() async {
    await _msgSub?.cancel();
    _msgSub = null;
    await _closeProposals();
    _clearContext();
    currentId = null;
    isDraft = false;
    draftAbout = null;
    draftPlaceId = null;
    draftTitle = null;
    _server = <Message>[];
    _pending.clear();
    notifyListeners();
  }

  /// Adds a file to the next message. Returns false, and adds nothing, when the
  /// message already holds [messageMaxFiles] (the server's limit).
  bool addAttachment(UploadItem item) {
    if (_pending.length >= messageMaxFiles) {
      return false;
    }
    _pending.add(_Attachment(item));
    notifyListeners();
    return true;
  }

  void removeAttachment(int index) {
    if (index >= 0 && index < _pending.length) {
      _pending.removeAt(index);
      notifyListeners();
    }
  }

  /// Accepts the message at once (ADR-037): it shows in the thread, is saved
  /// in the outbox on disk, and goes out in the background: the thread is made
  /// first when the chat is new, then the files upload, then the message is
  /// sent. Never waits for the network and is never refused for the link, a
  /// loading thread or a coach reply that is still coming. Returns false only
  /// when there is nothing to send (no chat open, or no text and no file).
  Future<bool> send(String text, {ChatAnswer? answer}) async {
    final String body = text.trim();
    if (currentId == null || (body.isEmpty && _pending.isEmpty)) {
      return false;
    }
    if (answer == null && logDone) {
      // A new log starts a new thread; what was picked for it comes along.
      final List<_Attachment> keep = List<_Attachment>.of(_pending);
      await startNewChat();
      _setLogContext();
      _pending.addAll(keep);
    }
    final String id = currentId!;
    final _Outgoing out = _Outgoing(
      messageId: newId(),
      threadId: id,
      // A log chat takes a message of files alone; elsewhere the text says so.
      text: body.isEmpty ? (isLogChat ? '' : 'See attached.') : body,
      files: List<_Attachment>.of(_pending),
      context: _sendContext,
      answer: answer,
    );
    // The first message of a new chat carries the making of the thread.
    Map<String, dynamic>? thread;
    if (isDraft) {
      final ThreadAbout? about = draftAbout;
      thread = <String, dynamic>{
        // The server names a chat about a program.
        if (about == null && draftTitle != null) 'title': draftTitle,
        if (draftPlaceId != null) 'placeId': draftPlaceId,
        if (about != null) 'about': about.toJson(),
      };
      isDraft = false;
      loadingMessages = true;
      _subscribeMessages(id);
      _subscribeProposals(id);
    }
    for (final _Attachment f in out.files) {
      _sentFiles[f.fileId] = f.item;
    }
    _pending.clear();
    _outgoing.add(out);
    error = null;
    notifyListeners();
    await _outbox.sendChat(
      messageId: out.messageId,
      threadId: id,
      text: out.text,
      files: <(String, UploadItem)>[for (final _Attachment f in out.files) (f.fileId, f.item)],
      context: out.context,
      answer: answer,
      thread: thread,
      createdAt: out.createdAt,
    );
    return true;
  }

  /// The outbox changed (a message went out, failed, or was loaded after a
  /// restart): messages the outbox holds that this store does not show yet are
  /// added, and the screen redraws.
  void _onOutbox({bool notify = true}) {
    final Set<String> known = <String>{for (final Message m in _server) m.id, for (final _Outgoing o in _outgoing) o.messageId};
    for (final QueuedChat q in _outbox.chats) {
      if (known.contains(q.messageId)) {
        continue;
      }
      for (int i = 0; i < q.files.length; i++) {
        _sentFiles[q.fileIds[i]] = q.files[i];
      }
      _outgoing.add(_Outgoing(
        messageId: q.messageId,
        threadId: q.threadId,
        text: q.text,
        files: <_Attachment>[for (int i = 0; i < q.files.length; i++) _Attachment(q.files[i], q.fileIds[i])],
        context: q.context,
        answer: q.answer,
        createdAt: q.createdAt,
      ));
    }
    if (notify) {
      notifyListeners();
    }
  }

  final Map<UploadItem, String> _voiceFiles = Map<UploadItem, String>.identity();

  /// Turns a recording into text for the composer's text field (ADR-034).
  /// Uploads the audio once (a second call for the same [audio] reuses the
  /// upload), then asks the server for the text. Nothing is sent to the coach
  /// and no message is stored. On success the server drops the audio and the
  /// local file is deleted. On failure the recording stays, so the same call
  /// can be made again. It never throws.
  Future<TranscriptResult> transcribeVoice(UploadItem audio) async {
    if (!connected) {
      return const TranscriptResult.failed('Offline. The recording is kept. Press Try again when the connection is back.');
    }
    try {
      final String fileId = _voiceFiles.putIfAbsent(audio, newId);
      if (!_voiceUploaded.contains(fileId)) {
        await _client.uploadFile(
            fileId: fileId, name: audio.name, mime: audio.mime, bytes: await audio.read());
        _voiceUploaded.add(fileId);
      }
      final TranscriptResult r = await _client.transcribeAudio(fileId);
      if (r.ok) {
        _voiceFiles.remove(audio);
        _voiceUploaded.remove(fileId);
        await _deleteLocal(audio);
      }
      return r;
    } on ConvexCallException catch (e) {
      return TranscriptResult.failed(e.message);
    } catch (_) {
      return const TranscriptResult.failed('Could not reach the server.');
    }
  }

  final Set<String> _voiceUploaded = <String>{};

  /// The person dropped a recording: remove the upload (when there is one) and the local file.
  Future<void> discardVoice(UploadItem audio) async {
    final String? fileId = _voiceFiles.remove(audio);
    if (fileId != null && _voiceUploaded.remove(fileId)) {
      try {
        await _client.removeFile(fileId);
      } catch (_) {} // an orphan upload is harmless
    }
    await _deleteLocal(audio);
  }

  /// Tries a failed voice message again: sends it if it never reached the
  /// server, else asks the server to read the recording again.
  Future<void> retryVoice(String messageId) async {
    if (sending) {
      return;
    }
    if (!connected) {
      error = chatOfflineMessage;
      notifyListeners();
      return;
    }
    error = null;
    try {
      await _client.retryVoice(messageId);
    } on ConvexCallException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not try again.';
    }
    notifyListeners();
  }

  Future<void> _deleteLocal(UploadItem item) async {
    if (item.bytes != null) {
      return;
    }
    try {
      await File(item.path).delete();
    } catch (_) {}
  }

  /// Sends the last user message of a thread whose coach reply failed again,
  /// with the same message id (an unsent message has [retryMessage]).
  Future<void> retry() async {
    if (!connected) {
      error = chatOfflineMessage;
      notifyListeners();
      return;
    }
    final Thread? t = currentThread;
    if (t == null || !t.failed) {
      return;
    }
    for (final Message m in _server.reversed) {
      if (m.mine) {
        error = null;
        notifyListeners();
        try {
          await _client.sendMessage(
              threadId: m.threadId,
              messageId: m.id,
              text: m.text,
              fileIds: m.fileIds,
              context: m.context);
        } on ConvexCallException catch (e) {
          error = e.message;
        } catch (_) {
          error = 'Could not send the message.';
        }
        notifyListeners();
        return;
      }
    }
  }

  @override
  void dispose() {
    _outbox.removeListener(_onOutbox);
    _threadSub?.cancel();
    _msgSub?.cancel();
    _propSub?.cancel();
    _goalSub?.cancel();
    _ctxSub?.cancel();
    super.dispose();
  }
}
