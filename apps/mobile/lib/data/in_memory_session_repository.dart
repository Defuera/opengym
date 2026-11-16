import 'session_repository.dart';

/// Keeps state in memory (as a JSON copy, so serialisation is exercised too).
/// For tests and the gallery.
class InMemorySessionRepository implements SessionRepository {
  InMemorySessionRepository([StoredState? initial])
      : _json = (initial ?? StoredState.empty()).toJson();

  Map<String, dynamic> _json;

  /// Number of saves so far.
  int saveCount = 0;

  /// What a fresh load would return right now.
  StoredState get state => StoredState.fromJson(_json);

  @override
  Future<StoredState> load() async => StoredState.fromJson(_json);

  @override
  Future<void> save(StoredState state) async {
    _json = state.toJson();
    saveCount++;
  }
}
