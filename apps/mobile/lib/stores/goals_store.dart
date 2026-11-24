import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../data/outbox.dart';
import '../data/outbox_ops.dart';
import '../models.dart';

/// Goals: a live subscription with the waiting writes applied on top. Edits go
/// to the outbox, so they work offline and a server update never undoes them.
class GoalsStore extends ChangeNotifier {
  GoalsStore({required ConvexClient client, required Outbox outbox})
      : _client = client,
        _outbox = outbox;

  final ConvexClient _client;
  final Outbox _outbox;

  List<Goal> _server = <Goal>[];
  List<Goal> goals = <Goal>[];
  bool loading = true;

  /// Readable problem (stream error or a refused write), else null.
  String? error;

  StreamSubscription<List<Goal>>? _sub;
  StreamSubscription<Rejection>? _rej;

  void start() {
    _sub ??= _client.watchGoals().listen(
      (List<Goal> list) {
        _server = list;
        loading = false;
        error = null;
        _rebuild();
      },
      onError: (Object e) {
        loading = false;
        error = e is ConvexCallException ? e.message : 'Could not load goals.';
        notifyListeners();
      },
    );
    _rej ??= _outbox.rejections.listen((Rejection r) {
      if (r.op.type.startsWith('goal.')) {
        error = r.message;
        notifyListeners();
      }
    });
    _outbox.addListener(_rebuild);
  }

  void _rebuild() {
    goals = overlayGoals(_server, _outbox.ops);
    notifyListeners();
  }

  Future<bool> markDone(Goal goal) async {
    error = null;
    await _outbox.updateGoal(goal.id, GoalPatch(status: goal.done ? 'active' : 'done'));
    return true;
  }

  Future<bool> remove(Goal goal) async {
    error = null;
    await _outbox.removeGoal(goal.id);
    return true;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _rej?.cancel();
    _outbox.removeListener(_rebuild);
    super.dispose();
  }
}
