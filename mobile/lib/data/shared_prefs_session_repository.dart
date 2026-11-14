import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'session_repository.dart';

/// Stores everything as one JSON string under a single key.
class SharedPrefsSessionRepository implements SessionRepository {
  static const String _key = 'opengym-v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _p() async {
    final SharedPreferences? cached = _prefs;
    if (cached != null) {
      return cached;
    }
    final SharedPreferences fresh = await SharedPreferences.getInstance();
    _prefs = fresh;
    return fresh;
  }

  @override
  Future<StoredState> load() async {
    final SharedPreferences p = await _p();
    final String? raw = p.getString(_key);
    if (raw == null) {
      return StoredState.empty();
    }
    try {
      return StoredState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return StoredState.empty();
    }
  }

  @override
  Future<void> save(StoredState state) async {
    final SharedPreferences p = await _p();
    await p.setString(_key, jsonEncode(state.toJson()));
  }
}
