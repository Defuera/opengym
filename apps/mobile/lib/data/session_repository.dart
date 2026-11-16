import '../models.dart';

/// Everything that is persisted.
class StoredState {
  const StoredState({
    required this.sessions,
    this.active,
    this.activeAt = 0,
  });

  final List<Session> sessions;
  final Session? active;
  final int activeAt;

  static StoredState empty() => const StoredState(sessions: <Session>[]);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sessions': sessions.map((Session s) => s.toJson()).toList(),
      'active': active?.toJson(),
      'activeAt': activeAt,
    };
  }

  factory StoredState.fromJson(Map<String, dynamic> j) {
    final List<Session> list = <Session>[];
    final Object? raw = j['sessions'];
    if (raw is List) {
      for (final Object? e in raw) {
        list.add(Session.fromJson(e as Map<String, dynamic>));
      }
    }
    final Object? a = j['active'];
    final Object? at = j['activeAt'];
    return StoredState(
      sessions: list,
      active: a == null ? null : Session.fromJson(a as Map<String, dynamic>),
      activeAt: at is num ? at.toInt() : 0,
    );
  }
}

/// Storage boundary. The store depends on this, never on a concrete backend.
abstract class SessionRepository {
  Future<StoredState> load();
  Future<void> save(StoredState state);
}
