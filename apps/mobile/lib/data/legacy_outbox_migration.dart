import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../store.dart';
import 'outbox.dart';

/// The first sync (REST) kept finished-session ids that were not yet pushed
/// under `opengym-sync-v1`. Move them into the new outbox once, then forget
/// the old key, so no finished session is lost by the switch to Convex.
Future<int> migrateLegacyOutbox(AppStore store, Outbox outbox) async {
  const String key = 'opengym-sync-v1';
  int moved = 0;
  try {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(key);
    if (raw == null) {
      return 0;
    }
    final Object? j = jsonDecode(raw);
    final Object? ids = j is Map ? j['outbox'] : null;
    if (ids is List) {
      for (final Object? id in ids) {
        final session = id is String ? store.sessionById(id) : null;
        if (session != null) {
          await outbox.saveSession(session);
          moved++;
        }
      }
    }
    await p.remove(key);
  } catch (_) {
    // A damaged old key is not worth blocking the start.
  }
  return moved;
}
