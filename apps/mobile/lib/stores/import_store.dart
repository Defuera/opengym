import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../data/upload_item.dart';
import '../models.dart';
import '../planner.dart';

/// File import on Convex. Pick files, upload each, start the import, and watch
/// the job on the live imports subscription (processed, total, counts, notes,
/// done or failed). Undo removes the import's data with one command.
class ImportStore extends ChangeNotifier {
  ImportStore({required ConvexClient client}) : _client = client;

  final ConvexClient _client;

  /// Called after an import was undone, so its sessions leave the local log.
  void Function(String importId)? onUndone;
  StreamSubscription<List<ImportJob>>? _sub;

  final List<UploadItem> picked = <UploadItem>[];
  List<ImportJob> past = <ImportJob>[];
  bool uploading = false;
  String? error;

  /// Ids made once per picked file and reused when the user tries again.
  final Map<UploadItem, String> _fileIds = <UploadItem, String>{};
  String? _activeId;
  ImportJob? _placeholder;

  /// Made once per attempt and kept when the start call fails, so a retry
  /// cannot start a second import.
  String? _attemptId;
  bool _seen = false;

  /// The import the user just started, as the server reports it (live).
  ImportJob? get job {
    final String? id = _activeId;
    if (id == null) {
      return null;
    }
    for (final ImportJob j in past) {
      if (j.id == id) {
        return j;
      }
    }
    return _placeholder;
  }

  bool get busy => uploading || (job?.running ?? false);

  void add(UploadItem item) {
    _attemptId = null;
    picked.add(item);
    notifyListeners();
  }

  void addAll(List<UploadItem> items) {
    if (items.isNotEmpty) {
      _attemptId = null;
      picked.addAll(items);
      notifyListeners();
    }
  }

  void removeAt(int i) {
    if (i >= 0 && i < picked.length) {
      _attemptId = null;
      _fileIds.remove(picked.removeAt(i));
      notifyListeners();
    }
  }

  /// Subscribe once. Past imports and the running one update live.
  void watchPast() {
    _sub ??= _client.watchImports().listen(
      (List<ImportJob> list) {
        past = list;
        final String? id = _activeId;
        if (id != null) {
          if (list.any((ImportJob j) => j.id == id)) {
            _seen = true;
          } else if (_seen) {
            _activeId = null; // removed on the server
            _placeholder = null;
          }
        }
        notifyListeners();
      },
      onError: (Object e) {
        error = e is ConvexCallException ? e.message : 'Could not load past imports.';
        notifyListeners();
      },
    );
  }

  /// Upload the picked files, then start the import. Progress arrives through
  /// the subscription; there is no polling.
  Future<void> start() async {
    if (picked.isEmpty || busy) {
      return;
    }
    uploading = true;
    error = null;
    _activeId = null;
    _placeholder = null;
    notifyListeners();
    final List<UploadItem> items = List<UploadItem>.from(picked);
    final String importId = _attemptId ??= newId();
    try {
      final List<String> ids = <String>[];
      for (final UploadItem it in items) {
        final String fileId = _fileIds.putIfAbsent(it, newId);
        await _client.uploadFile(
          fileId: fileId,
          name: it.name,
          mime: it.mime,
          bytes: await it.read(),
        );
        ids.add(fileId);
      }
      await _client.startImport(importId: importId, fileIds: ids);
      picked.clear();
      _fileIds.clear();
      _attemptId = null;
      _seen = false;
      _activeId = importId;
      _placeholder = ImportJob(
        id: importId,
        status: 'running',
        total: ids.length,
        processed: 0,
        counts: const ImportCounts(),
        notes: const <String>[],
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
    } on ConvexCallException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Upload failed.';
    }
    uploading = false;
    notifyListeners();
  }

  /// Removes the import's data on the server, then from this phone.
  Future<bool> undo(String jobId) async {
    try {
      await _client.removeImport(jobId);
      onUndone?.call(jobId);
      if (_activeId == jobId) {
        _activeId = null;
        _placeholder = null;
      }
      error = null;
      notifyListeners();
      return true;
    } on ConvexCallException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not undo the import.';
    }
    notifyListeners();
    return false;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
