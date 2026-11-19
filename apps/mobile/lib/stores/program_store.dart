import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../models.dart';

/// The programs of the person: a live subscription, read only. Offline, or on
/// an error, the last list stays and nothing new shows.
class ProgramStore extends ChangeNotifier {
  ProgramStore({required ConvexClient client}) : _client = client;

  final ConvexClient _client;

  /// Newest first, as the server sends them.
  List<Program> programs = <Program>[];
  bool loading = true;

  StreamSubscription<List<Program>>? _sub;

  void start() {
    _sub ??= _client.watchPrograms().listen(
      (List<Program> list) {
        programs = list;
        loading = false;
        notifyListeners();
      },
      onError: (Object _) {
        // No programs function on the server, or no link: keep the last list.
        loading = false;
        notifyListeners();
      },
    );
  }

  /// The programs that run now: status `active`.
  List<Program> get active => programs.where((Program p) => p.active).toList();

  Program? byId(String id) {
    for (final Program p in programs) {
      if (p.programId == id) {
        return p;
      }
    }
    return null;
  }

  Future<void> setStatus(String programId, String status) => _client.setProgramStatus(programId, status);

  Future<void> remove(String programId) => _client.removeProgram(programId);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
