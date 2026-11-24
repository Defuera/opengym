import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../data/outbox.dart';
import '../data/outbox_ops.dart';
import '../models.dart';

/// Context notes the coach reads as training preferences. Same shape as
/// [GoalsStore]: live subscription, writes through the outbox.
class ContextStore extends ChangeNotifier {
  ContextStore({required ConvexClient client, required Outbox outbox})
      : _client = client,
        _outbox = outbox;

  final ConvexClient _client;
  final Outbox _outbox;

  List<ContextItem> _server = <ContextItem>[];
  List<ContextItem> items = <ContextItem>[];
  bool loading = true;
  String? error;
  StreamSubscription<List<ContextItem>>? _sub;

  void start() {
    _sub ??= _client.watchContext().listen(
      (List<ContextItem> list) {
        _server = list;
        loading = false;
        error = null;
        _rebuild();
      },
      onError: (Object e) {
        loading = false;
        error = e is ConvexCallException ? e.message : 'Could not load notes.';
        notifyListeners();
      },
    );
    _outbox.addListener(_rebuild);
  }

  void _rebuild() {
    items = overlayContext(_server, _outbox.ops);
    notifyListeners();
  }

  Future<void> setActive(ContextItem item, bool active) =>
      _outbox.updateContext(item.id, ContextPatch(active: active));

  Future<void> remove(ContextItem item) => _outbox.removeContext(item.id);

  @override
  void dispose() {
    _sub?.cancel();
    _outbox.removeListener(_rebuild);
    super.dispose();
  }
}
