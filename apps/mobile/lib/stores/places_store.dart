import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../models.dart';

/// The places the coach knows: a live subscription, read only. A server that
/// has no places yet (or an error) leaves the list empty and breaks nothing.
class PlacesStore extends ChangeNotifier {
  PlacesStore({required ConvexClient client}) : _client = client;

  final ConvexClient _client;

  /// Sorted by name, as the server sends them.
  List<Place> places = <Place>[];
  bool loading = true;

  /// Names learned from a coach proposal before the list holds them.
  final Map<String, Place> _known = <String, Place>{};

  StreamSubscription<List<Place>>? _sub;

  void start() {
    _sub ??= _client.watchPlaces().listen(
      (List<Place> list) {
        places = list;
        loading = false;
        notifyListeners();
      },
      onError: (Object _) {
        // No places function on the server, or the call failed: no places.
        loading = false;
        notifyListeners();
      },
    );
  }

  /// The place with [id]: from the list, else one learned from a proposal.
  Place? byId(String? id) {
    if (id == null) {
      return null;
    }
    for (final Place p in places) {
      if (p.id == id) {
        return p;
      }
    }
    return _known[id];
  }

  /// Remembers the name of a place the coach proposed, so the mark can show
  /// it while the list has not caught up.
  void learn(PlaceRef ref) {
    if (byId(ref.id) == null && ref.name.isNotEmpty) {
      _known[ref.id] = Place(id: ref.id, name: ref.name);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
