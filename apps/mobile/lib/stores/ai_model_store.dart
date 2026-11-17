import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../models.dart';

/// The "Coach model" setting: watches `queries/settings:ai` and writes the
/// owner's choice. Needs a connection: writes are not queued in the outbox.
class AiModelStore extends ChangeNotifier {
  AiModelStore({required ConvexClient client}) : _client = client;

  final ConvexClient _client;
  StreamSubscription<AiSettings>? _sub;

  /// Null until the first answer.
  AiSettings? settings;
  bool refreshing = false;

  /// A write the user asked for and the server has not shown yet. [_hasPending] tells null (default) from none.
  String? _pending;
  bool _hasPending = false;

  /// Why the last write failed, in words for the user.
  String? error;

  void start() {
    _sub ??= _client.watchAiSettings().listen(
      (AiSettings s) {
        settings = s;
        if (_hasPending && s.override == _pending) {
          _hasPending = false;
        }
        notifyListeners();
      },
      onError: (Object e) {
        error = _message(e, 'Could not load the model setting.');
        notifyListeners();
      },
    );
  }

  /// The model id picked now: the one just chosen, else the server's choice. Null: the default.
  String? get selected => _hasPending ? _pending : settings?.override;

  /// The model in use, as far as the app knows.
  String? get effective => selected ?? settings?.defaultModel;

  /// Picks [model] (null: the default). Shows at once; goes back if the server refuses.
  Future<void> pick(String? model) async {
    if (model == selected) {
      return;
    }
    _pending = model;
    _hasPending = true;
    error = null;
    notifyListeners();
    try {
      await _client.setAiModel(model);
    } catch (e) {
      _hasPending = false;
      error = _message(e, 'Could not save the model.');
    }
    notifyListeners();
  }

  /// Reloads the provider's model list. The new list arrives through the watch.
  Future<void> refresh() async {
    if (refreshing) {
      return;
    }
    refreshing = true;
    error = null;
    notifyListeners();
    try {
      await _client.refreshModels();
    } catch (e) {
      error = _message(e, 'Could not ask for the list.');
    }
    refreshing = false;
    notifyListeners();
  }

  static String _message(Object e, String fallback) => e is ConvexCallException ? e.message : fallback;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
