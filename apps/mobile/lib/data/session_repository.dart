import '../models.dart';

/// Everything that is persisted.
class StoredState {
  const StoredState({
    required this.sessions,
    this.active,
    this.activeAt = 0,
    this.activeRev = 0,
    this.activeDirty = false,
    this.pendingClear,
    this.undo,
    this.undoAt = 0,
  });

  /// The session as it was open just before it was finished (with its sets
  /// that were not done), and when it was finished. For "Continue session".
  final Session? undo;
  final int undoAt;

  final List<Session> sessions;
  final Session? active;
  final int activeAt;

  /// The server's revision of the open session that the phone's copy is based on (0: none).
  final int activeRev;

  /// The open session has a change the server does not hold yet.
  final bool activeDirty;

  /// The id of a session that ended on the phone and is still open on the server.
  final String? pendingClear;

  static StoredState empty() => const StoredState(sessions: <Session>[]);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sessions': sessions.map((Session s) => s.toJson()).toList(),
      'active': active?.toJson(),
      'activeAt': activeAt,
      'activeRev': activeRev,
      'activeDirty': activeDirty,
      if (pendingClear != null) 'pendingClear': pendingClear,
      if (undo != null) 'undo': undo!.toJson(),
      if (undo != null) 'undoAt': undoAt,
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
    final Object? rev = j['activeRev'];
    final Object? clear = j['pendingClear'];
    final Object? undo = j['undo'];
    final Object? undoAt = j['undoAt'];
    return StoredState(
      sessions: list,
      active: a == null ? null : Session.fromJson(a as Map<String, dynamic>),
      activeAt: at is num ? at.toInt() : 0,
      activeRev: rev is num ? rev.toInt() : 0,
      // A copy from before the sync existed (no flag) counts as not yet sent.
      activeDirty: a != null && j['activeDirty'] != false,
      pendingClear: clear is String && clear.isNotEmpty ? clear : null,
      undo: undo is Map<String, dynamic> ? Session.fromJson(undo) : null,
      undoAt: undoAt is num ? undoAt.toInt() : 0,
    );
  }
}

/// Storage boundary. The store depends on this, never on a concrete backend.
abstract class SessionRepository {
  Future<StoredState> load();
  Future<void> save(StoredState state);
}
