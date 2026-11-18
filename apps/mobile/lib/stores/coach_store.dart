import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../data/upload_item.dart';
import '../models.dart';
import '../planner.dart';

const String chatOfflineMessage = 'Chat needs a connection. Nothing was sent.';

class _Attachment {
  _Attachment(this.item) : fileId = newId();

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
  }) : createdAt = DateTime.now().millisecondsSinceEpoch;

  final String messageId;
  final String threadId;
  final String text;
  final List<_Attachment> files;
  final int createdAt;

  /// The send call failed (after the user pressed send). Retry is offered.
  bool unsent = false;

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
/// Chat needs a connection. It is not queued in the outbox.
class CoachStore extends ChangeNotifier {
  CoachStore({required ConvexClient client, required bool Function() isConnected})
      : _client = client,
        _isConnected = isConnected;

  final ConvexClient _client;
  final bool Function() _isConnected;

  List<Thread> threads = <Thread>[];
  String? currentId;

  /// The open chat is new and not on the server yet. It is created with the
  /// first message, so backing out leaves no empty thread behind.
  bool isDraft = false;

  /// Set on a draft chat about a place: the place id and the thread title.
  String? draftPlaceId;
  String? draftTitle;
  bool loadingThreads = true;
  bool loadingMessages = false;

  /// True while a message is being uploaded and sent.
  bool sending = false;

  /// Readable problem for the screen, else null.
  String? error;

  List<Message> _server = <Message>[];
  List<Goal> _goals = <Goal>[];
  List<ContextItem> _context = <ContextItem>[];
  final List<_Outgoing> _outgoing = <_Outgoing>[];
  final List<_Attachment> _pending = <_Attachment>[];

  StreamSubscription<List<Thread>>? _threadSub;
  StreamSubscription<List<Message>>? _msgSub;
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

  _Outgoing? get _unsent {
    for (final _Outgoing o in _outgoing.reversed) {
      if (o.unsent && o.threadId == currentId) {
        return o;
      }
    }
    return null;
  }

  /// Short problem text next to a retry action, else null. Either the last
  /// send did not reach the server, or the coach job failed.
  String? get retryReason {
    if (_unsent != null) {
      return error ?? 'The message was not sent.';
    }
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
        notifyListeners();
      },
      onError: (Object e) {
        loadingThreads = false;
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
  Future<void> startNewChat({String? placeId, String? title}) async {
    await _msgSub?.cancel();
    _msgSub = null;
    currentId = newId();
    isDraft = true;
    draftPlaceId = placeId;
    draftTitle = placeId == null ? null : title;
    _server = <Message>[];
    _pending.clear();
    loadingMessages = false;
    error = null;
    notifyListeners();
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
    currentId = id;
    isDraft = false;
    draftPlaceId = null;
    draftTitle = null;
    _server = <Message>[];
    _pending.clear();
    loadingMessages = true;
    error = null;
    notifyListeners();
    _subscribeMessages(id);
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

  Future<void> closeThread() async {
    await _msgSub?.cancel();
    _msgSub = null;
    currentId = null;
    isDraft = false;
    draftPlaceId = null;
    draftTitle = null;
    _server = <Message>[];
    _pending.clear();
    notifyListeners();
  }

  void addAttachment(UploadItem item) {
    _pending.add(_Attachment(item));
    notifyListeners();
  }

  void removeAttachment(int index) {
    if (index >= 0 && index < _pending.length) {
      _pending.removeAt(index);
      notifyListeners();
    }
  }

  /// Accepts the message: it shows at once, then files upload, then it is
  /// sent. Returns false when nothing was accepted (empty, busy, offline), so
  /// the screen keeps the text. A failure after acceptance shows [retryReason].
  Future<bool> send(String text) async {
    final String? id = currentId;
    final String body = text.trim();
    if (id == null || sending || (body.isEmpty && _pending.isEmpty)) {
      return false;
    }
    if (!connected) {
      error = chatOfflineMessage;
      notifyListeners();
      return false;
    }
    final _Outgoing out = _Outgoing(
      messageId: newId(),
      threadId: id,
      text: body.isEmpty ? 'See attached.' : body,
      files: List<_Attachment>.of(_pending),
    );
    if (isDraft) {
      // First message of a new chat: create the thread, then send.
      sending = true;
      notifyListeners();
      final String? made = await _createDraft(id);
      sending = false;
      if (made == null) {
        notifyListeners();
        return false;
      }
    }
    for (final _Attachment f in out.files) {
      _sentFiles[f.fileId] = f.item;
    }
    _pending.clear();
    _outgoing.add(out);
    await _deliver(out);
    return true;
  }

  Future<String?> _createDraft(String id) async {
    try {
      await _client.createThread(threadId: id, title: draftTitle, placeId: draftPlaceId);
      isDraft = false;
      draftPlaceId = null;
      draftTitle = null;
      error = null;
      loadingMessages = true;
      _subscribeMessages(id);
      return id;
    } on ConvexCallException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not create the thread.';
    }
    return null;
  }

  /// Sends again with the same message id: an unsent message, or the last
  /// user message of a thread whose coach reply failed.
  Future<void> retry() async {
    if (sending) {
      return;
    }
    if (!connected) {
      error = chatOfflineMessage;
      notifyListeners();
      return;
    }
    final _Outgoing? out = _unsent;
    if (out != null) {
      await _deliver(out);
      return;
    }
    final Thread? t = currentThread;
    if (t == null || !t.failed) {
      return;
    }
    for (final Message m in _server.reversed) {
      if (m.mine) {
        sending = true;
        error = null;
        notifyListeners();
        try {
          await _client.sendMessage(
              threadId: m.threadId, messageId: m.id, text: m.text, fileIds: m.fileIds);
        } on ConvexCallException catch (e) {
          error = e.message;
        } catch (_) {
          error = 'Could not send the message.';
        }
        sending = false;
        notifyListeners();
        return;
      }
    }
  }

  Future<void> _deliver(_Outgoing out) async {
    sending = true;
    out.unsent = false;
    error = null;
    notifyListeners();
    try {
      for (final _Attachment f in out.files) {
        if (!f.uploaded) {
          await _client.uploadFile(
            fileId: f.fileId,
            name: f.item.name,
            mime: f.item.mime,
            bytes: await f.item.read(),
          );
          f.uploaded = true;
        }
      }
      await _client.sendMessage(
        threadId: out.threadId,
        messageId: out.messageId,
        text: out.text,
        fileIds: <String>[for (final _Attachment f in out.files) f.fileId],
      );
    } on ConvexCallException catch (e) {
      error = e.message;
      out.unsent = true;
    } catch (_) {
      error = 'Could not send the message.';
      out.unsent = true;
    }
    sending = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _threadSub?.cancel();
    _msgSub?.cancel();
    _goalSub?.cancel();
    _ctxSub?.cancel();
    super.dispose();
  }
}
