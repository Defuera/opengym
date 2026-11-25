import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the person chose about the health store, and what was done, kept on
/// the phone. Both switches start off.
class TrackerPrefsState {
  const TrackerPrefsState({
    this.readOn = false,
    this.writeOn = false,
    this.lastSyncAt,
    this.lastDays = 0,
    this.lastWorkouts = 0,
    this.writtenIds = const <String>{},
  });

  /// Read the health store and send it to the coach.
  final bool readOn;

  /// Write each finished session to the health store.
  final bool writeOn;

  /// When the last send went through, and what it held.
  final DateTime? lastSyncAt;
  final int lastDays;
  final int lastWorkouts;

  /// Ids of the sessions already written to the store (write once per session).
  final Set<String> writtenIds;

  TrackerPrefsState copyWith({
    bool? readOn,
    bool? writeOn,
    DateTime? lastSyncAt,
    int? lastDays,
    int? lastWorkouts,
    Set<String>? writtenIds,
  }) =>
      TrackerPrefsState(
        readOn: readOn ?? this.readOn,
        writeOn: writeOn ?? this.writeOn,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        lastDays: lastDays ?? this.lastDays,
        lastWorkouts: lastWorkouts ?? this.lastWorkouts,
        writtenIds: writtenIds ?? this.writtenIds,
      );
}

abstract class TrackerPrefs {
  Future<TrackerPrefsState> load();
  Future<void> save(TrackerPrefsState state);
}

class SharedPrefsTrackerPrefs implements TrackerPrefs {
  static const String _read = 'opengym-tracker-read';
  static const String _write = 'opengym-tracker-write';
  static const String _at = 'opengym-tracker-last-sync';
  static const String _days = 'opengym-tracker-last-days';
  static const String _workouts = 'opengym-tracker-last-workouts';
  static const String _written = 'opengym-tracker-written';

  /// Kept short: a session older than this is never written anyway.
  static const int writtenMax = 500;

  @override
  Future<TrackerPrefsState> load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final int? at = p.getInt(_at);
    return TrackerPrefsState(
      readOn: p.getBool(_read) ?? false,
      writeOn: p.getBool(_write) ?? false,
      lastSyncAt: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
      lastDays: p.getInt(_days) ?? 0,
      lastWorkouts: p.getInt(_workouts) ?? 0,
      writtenIds: (p.getStringList(_written) ?? const <String>[]).toSet(),
    );
  }

  @override
  Future<void> save(TrackerPrefsState s) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setBool(_read, s.readOn);
    await p.setBool(_write, s.writeOn);
    final DateTime? at = s.lastSyncAt;
    if (at != null) {
      await p.setInt(_at, at.millisecondsSinceEpoch);
    }
    await p.setInt(_days, s.lastDays);
    await p.setInt(_workouts, s.lastWorkouts);
    final List<String> ids = s.writtenIds.toList();
    await p.setStringList(_written, ids.length > writtenMax ? ids.sublist(ids.length - writtenMax) : ids);
  }
}

class InMemoryTrackerPrefs implements TrackerPrefs {
  InMemoryTrackerPrefs([this.state = const TrackerPrefsState()]);

  TrackerPrefsState state;
  int saves = 0;

  @override
  Future<TrackerPrefsState> load() async => state;

  @override
  Future<void> save(TrackerPrefsState s) async {
    saves++;
    state = s;
  }
}

/// The one copy of the tracker choices in memory. The sync and the writer both
/// change it, so neither overwrites the other's fields.
class TrackerSettings extends ChangeNotifier {
  TrackerSettings(this._prefs);

  final TrackerPrefs _prefs;
  TrackerPrefsState state = const TrackerPrefsState();

  Future<void> load() async {
    try {
      state = await _prefs.load();
    } catch (_) {
      state = const TrackerPrefsState();
    }
    notifyListeners();
  }

  /// Applies [change] to the state, tells listeners, then saves. A failed save
  /// keeps the choice in memory; the next change saves it.
  Future<void> update(TrackerPrefsState Function(TrackerPrefsState s) change) async {
    state = change(state);
    notifyListeners();
    try {
      await _prefs.save(state);
    } catch (_) {
      // Kept in memory only.
    }
  }
}
