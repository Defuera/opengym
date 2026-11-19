import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/convex_client.dart';
import '../models.dart';

/// The pictures of exercises. The app asks the server for art once per name
/// per run, then follows the art state with one live query. Offline, not set
/// up, or any error: nothing happens and nothing shows.
class ExerciseArtStore extends ChangeNotifier {
  ExerciseArtStore({
    required ConvexClient client,
    required bool Function() isConnected,
    ImageProvider Function(String url)? imageFor,
  })  : _client = client,
        _isConnected = isConnected,
        _imageFor = imageFor ?? NetworkImage.new;

  /// The server answers at most this many names in one query.
  static const int maxWatched = 30;

  /// The server takes at most this many names in one request.
  static const int maxRequested = 12;

  final ConvexClient _client;
  final bool Function() _isConnected;
  final ImageProvider Function(String url) _imageFor;

  final Set<String> _requested = <String>{};
  final Map<String, String> _urls = <String, String>{};
  List<String> _watching = <String>[];
  StreamSubscription<List<ExerciseArt>>? _sub;

  /// Asks for art for [names] (once per name per run) and follows their state.
  void track(List<String> names) {
    if (!_isConnected()) {
      return;
    }
    final Map<String, String> byKey = <String, String>{};
    for (final String n in names) {
      final String t = n.trim();
      final String k = exerciseArtKey(t);
      if (k.isNotEmpty && k.length <= 80) {
        byKey.putIfAbsent(k, () => t);
      }
    }
    final List<String> keys = byKey.keys.take(maxWatched).toList();
    _request(<String>[for (final String k in keys) if (!_requested.contains(k)) k], byKey);
    if (keys.length == _watching.length && keys.every(_watching.contains)) {
      return;
    }
    _watching = keys;
    _sub?.cancel();
    _sub = null;
    if (keys.isEmpty) {
      return;
    }
    _sub = _client.watchExerciseArt(<String>[for (final String k in keys) byKey[k]!]).listen(
      (List<ExerciseArt> list) {
        _urls
          ..clear()
          ..addEntries(<MapEntry<String, String>>[
            for (final ExerciseArt a in list)
              if (a.ready) MapEntry<String, String>(exerciseArtKey(a.name), a.url!),
          ]);
        notifyListeners();
      },
      onError: (Object _) {
        // No such function on the server, or the call failed: no art.
      },
    );
  }

  void _request(List<String> fresh, Map<String, String> byKey) {
    for (int i = 0; i < fresh.length; i += maxRequested) {
      final List<String> chunk = fresh.sublist(i, i + maxRequested > fresh.length ? fresh.length : i + maxRequested);
      _requested.addAll(chunk);
      unawaited(_client.requestExerciseArt(<String>[for (final String k in chunk) byKey[k]!]).catchError((Object _) {
        // Try again at the next track call.
        _requested.removeAll(chunk);
      }));
    }
  }

  /// The URL of the ready picture of [name], else null.
  String? urlFor(String name) => _urls[exerciseArtKey(name)];

  /// The image of [name] when ready, else null.
  ImageProvider? imageFor(String name) {
    final String? u = urlFor(name);
    return u == null ? null : _imageFor(u);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
