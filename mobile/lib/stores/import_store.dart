import 'package:flutter/foundation.dart';

import '../data/api/open_gym_api.dart';
import '../data/sync_service.dart';
import '../models.dart';

/// Upload files and photos for import, poll the job, undo it.
class ImportStore extends ChangeNotifier {
  ImportStore({
    required OpenGymApi api,
    required SyncService sync,
    this.pollEvery = const Duration(seconds: 2),
    this.maxPolls = 300,
  })  : _api = api,
        _sync = sync;

  final OpenGymApi _api;
  final SyncService _sync;
  final Duration pollEvery;
  final int maxPolls;

  final List<UploadItem> picked = <UploadItem>[];
  List<ImportJob> past = <ImportJob>[];
  ImportJob? job;
  bool uploading = false;
  String? error;
  bool _disposed = false;

  bool get busy => uploading || (job?.running ?? false);

  void add(UploadItem item) {
    picked.add(item);
    notifyListeners();
  }

  void addAll(List<UploadItem> items) {
    if (items.isNotEmpty) {
      picked.addAll(items);
      notifyListeners();
    }
  }

  void removeAt(int i) {
    if (i >= 0 && i < picked.length) {
      picked.removeAt(i);
      notifyListeners();
    }
  }

  Future<void> loadPast() async {
    try {
      past = await _api.listImports();
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not load past imports.';
    }
    notifyListeners();
  }

  /// Upload the picked files, then poll until the job is done or failed.
  Future<void> start() async {
    if (picked.isEmpty || busy) {
      return;
    }
    uploading = true;
    error = null;
    job = null;
    notifyListeners();
    try {
      job = await _api.startImport(List<UploadItem>.from(picked));
      picked.clear();
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Upload failed.';
    }
    uploading = false;
    notifyListeners();
    if (job != null) {
      await _poll();
    }
  }

  Future<void> _poll() async {
    int failures = 0;
    for (int i = 0; i < maxPolls; i++) {
      final ImportJob? j = job;
      if (j == null || j.finished || _disposed) {
        break;
      }
      await Future<void>.delayed(pollEvery);
      if (_disposed) {
        return;
      }
      try {
        job = await _api.getImport(j.id);
        failures = 0;
        error = null;
      } on ApiException catch (e) {
        error = e.message;
        failures++;
      } catch (_) {
        failures++;
      }
      notifyListeners();
      if (failures >= 5) {
        return;
      }
    }
    final ImportJob? done = job;
    if (done != null && done.finished) {
      await _sync.pull(full: true);
      await loadPast();
    }
  }

  /// DELETE /v1/import/:id, then drop its sessions from this phone.
  Future<bool> undo(String jobId) async {
    try {
      await _api.deleteImport(jobId);
      _sync.forgetImport(jobId);
      if (job?.id == jobId) {
        job = null;
      }
      past = past.where((ImportJob j) => j.id != jobId).toList();
      error = null;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not undo the import.';
    }
    notifyListeners();
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
