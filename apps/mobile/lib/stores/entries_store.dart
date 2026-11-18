import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../data/upload_item.dart';
import '../models.dart';
import '../planner.dart';

const String entriesOfflineMessage = 'Notes need a connection. Nothing was saved.';

/// A picked file that is not on the server yet. It keeps its file id and
/// whether it is uploaded, so a retry never uploads it twice.
class NewEntryFile {
  NewEntryFile(this.item) : fileId = newId();

  final UploadItem item;
  final String fileId;
  bool uploaded = false;
}

/// Notes: a live subscription, plus save (upload new files, then the command)
/// and remove. Notes need a connection: they are not queued in the outbox.
class EntriesStore extends ChangeNotifier {
  EntriesStore({required ConvexClient client, required bool Function() isConnected})
      : _client = client,
        _isConnected = isConnected;

  final ConvexClient _client;
  final bool Function() _isConnected;

  /// Newest first by time.
  List<LogEntry> entries = <LogEntry>[];
  bool loading = true;

  /// True while a save or a delete runs.
  bool busy = false;

  /// Short line while a save runs: "Uploading 1 of 2…" or "Saving…".
  String? progress;

  /// Readable problem of the last save, delete or stream, else null.
  String? error;

  StreamSubscription<List<LogEntry>>? _sub;

  void start() {
    _sub ??= _client.watchEntries(limit: 200).listen(
      (List<LogEntry> list) {
        entries = list;
        loading = false;
        notifyListeners();
      },
      onError: (Object e) {
        loading = false;
        error = e is ConvexCallException ? e.message : 'Could not load notes.';
        notifyListeners();
      },
    );
  }

  LogEntry? byId(String id) {
    for (final LogEntry e in entries) {
      if (e.id == id) {
        return e;
      }
    }
    return null;
  }

  void clearError() {
    if (error != null) {
      error = null;
      notifyListeners();
    }
  }

  /// Uploads the files in [added] that are not uploaded yet, then saves the
  /// note with [keep] (files it already has) and [added]. Returns true when
  /// saved. On false, [error] says why; the caller keeps its form and may
  /// call again with the same [entryId] and [added].
  Future<bool> save({
    required String entryId,
    required String text,
    required int at,
    int? createdAt,
    List<String> keep = const <String>[],
    List<NewEntryFile> added = const <NewEntryFile>[],
  }) async {
    if (busy) {
      return false;
    }
    final String body = text.trim();
    if (body.isEmpty && keep.isEmpty && added.isEmpty) {
      return false;
    }
    if (!_isConnected()) {
      error = entriesOfflineMessage;
      notifyListeners();
      return false;
    }
    busy = true;
    error = null;
    progress = added.any((NewEntryFile f) => !f.uploaded) ? 'Uploading…' : 'Saving…';
    notifyListeners();
    try {
      final int total = added.where((NewEntryFile f) => !f.uploaded).length;
      int n = 0;
      for (final NewEntryFile f in added) {
        if (f.uploaded) {
          continue;
        }
        n++;
        progress = 'Uploading $n of $total…';
        notifyListeners();
        await _client.uploadFile(
          fileId: f.fileId,
          name: f.item.name,
          mime: f.item.mime,
          bytes: await f.item.read(),
        );
        f.uploaded = true;
      }
      progress = 'Saving…';
      notifyListeners();
      await _client.saveEntry(
        entryId: entryId,
        text: body,
        fileIds: <String>[...keep, for (final NewEntryFile f in added) f.fileId],
        at: at,
        createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch,
      );
      busy = false;
      progress = null;
      notifyListeners();
      return true;
    } on ConvexCallException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not save the note.';
    }
    busy = false;
    progress = null;
    notifyListeners();
    return false;
  }

  /// Deletes the note and its files. Returns true when done.
  Future<bool> remove(String entryId) async {
    if (busy) {
      return false;
    }
    if (!_isConnected()) {
      error = entriesOfflineMessage;
      notifyListeners();
      return false;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _client.removeEntry(entryId);
      busy = false;
      notifyListeners();
      return true;
    } on ConvexCallException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not delete the note.';
    }
    busy = false;
    notifyListeners();
    return false;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
