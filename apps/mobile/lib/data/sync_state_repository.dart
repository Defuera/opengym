import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// What sync must remember between runs: finished session ids not yet pushed,
/// and the newest endedAt seen from the server.
class SyncState {
  const SyncState({this.outbox = const <String>[], this.lastPull = 0});

  final List<String> outbox;
  final int lastPull;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'outbox': outbox, 'lastPull': lastPull};
  }

  factory SyncState.fromJson(Map<String, dynamic> j) {
    final List<String> ids = <String>[];
    final Object? raw = j['outbox'];
    if (raw is List) {
      for (final Object? e in raw) {
        if (e is String) {
          ids.add(e);
        }
      }
    }
    final Object? lp = j['lastPull'];
    return SyncState(outbox: ids, lastPull: lp is num ? lp.toInt() : 0);
  }
}

abstract class SyncStateRepository {
  Future<SyncState> load();
  Future<void> save(SyncState state);
}

class SharedPrefsSyncStateRepository implements SyncStateRepository {
  static const String _key = 'opengym-sync-v1';

  @override
  Future<SyncState> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(_key);
    if (raw == null) {
      return const SyncState();
    }
    try {
      return SyncState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const SyncState();
    }
  }

  @override
  Future<void> save(SyncState state) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(state.toJson()));
  }
}

class InMemorySyncStateRepository implements SyncStateRepository {
  InMemorySyncStateRepository([SyncState initial = const SyncState()])
      : _json = initial.toJson();

  Map<String, dynamic> _json;

  @override
  Future<SyncState> load() async => SyncState.fromJson(_json);

  @override
  Future<void> save(SyncState state) async {
    _json = state.toJson();
  }
}
