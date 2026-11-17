import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api/open_gym_api.dart';
import '../data/convex_client.dart';
import '../models.dart';

/// Past imports (a live Convex subscription) and undo (a Convex command).
///
/// Upload and the running job still use the old REST client ([OpenGymApi]).
/// That is the seam for the next step: `commands/files:*` and
/// `commands/imports:start` replace [start] and [_poll]; the running job then
/// also arrives through [ConvexClient.watchImports].
class ImportStore extends ChangeNotifier {
  ImportStore({
    required OpenGymApi api,
    required ConvexClient client,
    this.pollEvery = const Duration(seconds: 2),
    this.maxPolls = 300,
  })  : _api = api,
        _client = client;

  final OpenGymApi _api;
  final ConvexClient _client;

  /// Called after an import was undone, so its sessions leave the local log.
  void Function(String importId)? onUndone;
  StreamSubscription<List<ImportJob>>? _sub;
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

  /// Subscribe once. Past imports update live.
  void watchPast() {
    _sub ??= _client.watchImports().listen(
      (List<ImportJob> list) {
        past = list;
        notifyListeners();
      },
      onError: (Object e) {
        error = e is ConvexCallException ? e.message : 'Could not load past imports.';
        notifyListeners();
      },
    );
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
    // Sessions and past imports arrive through their live subscriptions.
  }

  /// Removes the import's data on the server, then from this phone.
  Future<bool> undo(String jobId) async {
    try {
      await _client.removeImport(jobId);
      onUndone?.call(jobId);
      if (job?.id == jobId) {
        job = null;
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
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
