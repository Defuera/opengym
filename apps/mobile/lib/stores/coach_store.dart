import 'package:flutter/foundation.dart';

import '../data/api/open_gym_api.dart';
import '../models.dart';

class _Pending {
  _Pending(this.item);

  final UploadItem item;
  String? fileId;
}

/// Threads, messages and attachments for the coach chat.
class CoachStore extends ChangeNotifier {
  CoachStore({required OpenGymApi api}) : _api = api;

  final OpenGymApi _api;

  List<Thread> threads = <Thread>[];
  List<Message> messages = <Message>[];
  String? currentId;
  bool loadingThreads = false;
  bool loadingMessages = false;
  bool sending = false;

  /// Inline error for the screen (load or send problems).
  String? error;

  /// Short labels for goals/context the last reply saved, e.g. "Goal: ...".
  List<String> saved = <String>[];

  final List<_Pending> _pending = <_Pending>[];

  List<UploadItem> get attachments =>
      _pending.map((_Pending p) => p.item).toList();

  Thread? get currentThread {
    for (final Thread t in threads) {
      if (t.id == currentId) {
        return t;
      }
    }
    return null;
  }

  Future<void> loadThreads() async {
    loadingThreads = true;
    notifyListeners();
    try {
      threads = await _api.listThreads();
      error = null;
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not load threads.';
    }
    loadingThreads = false;
    notifyListeners();
  }

  Future<Thread?> createThread(String title) async {
    try {
      final Thread t = await _api.createThread(title);
      threads = <Thread>[t, ...threads];
      error = null;
      notifyListeners();
      return t;
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not create the thread.';
    }
    notifyListeners();
    return null;
  }

  Future<void> deleteThread(String id) async {
    try {
      await _api.deleteThread(id);
      threads = threads.where((Thread t) => t.id != id).toList();
      if (currentId == id) {
        currentId = null;
        messages = <Message>[];
      }
      error = null;
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not delete the thread.';
    }
    notifyListeners();
  }

  Future<void> openThread(String id) async {
    currentId = id;
    messages = <Message>[];
    saved = <String>[];
    _pending.clear();
    loadingMessages = true;
    error = null;
    notifyListeners();
    try {
      final List<Message> got = await _api.listMessages(id);
      if (currentId == id) {
        messages = got;
      }
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not load messages.';
    }
    loadingMessages = false;
    notifyListeners();
  }

  void addAttachment(UploadItem item) {
    _pending.add(_Pending(item));
    notifyListeners();
  }

  void removeAttachment(int index) {
    if (index >= 0 && index < _pending.length) {
      _pending.removeAt(index);
      notifyListeners();
    }
  }

  /// Upload attachments, then post the message. True when the reply arrived.
  /// On failure the text and attachments stay, so the user can try again.
  Future<bool> send(String text) async {
    final String id = currentId ?? '';
    final String body = text.trim();
    if (id.isEmpty || sending || (body.isEmpty && _pending.isEmpty)) {
      return false;
    }
    sending = true;
    error = null;
    notifyListeners();
    try {
      final List<String> ids = <String>[];
      for (final _Pending p in _pending) {
        p.fileId ??= (await _api.uploadFile(p.item)).id;
        ids.add(p.fileId!);
      }
      final SendResult r = await _api.sendMessage(
        id,
        body.isEmpty ? 'See attached.' : body,
        fileIds: ids,
      );
      if (currentId == id) {
        messages = <Message>[...messages, r.userMessage, r.assistantMessage];
      }
      saved = <String>[
        for (final Goal g in r.goals) 'Goal: ${g.title}',
        for (final ContextItem c in r.context) c.text,
      ];
      _pending.clear();
      _touch(id, r.assistantMessage.text);
      sending = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not send the message.';
    }
    sending = false;
    notifyListeners();
    return false;
  }

  void _touch(String id, String last) {
    threads = threads.map((Thread t) {
      if (t.id != id) {
        return t;
      }
      return Thread(
        id: t.id,
        title: t.title,
        createdAt: t.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        summary: t.summary,
        lastMessage: last,
      );
    }).toList();
  }
}
