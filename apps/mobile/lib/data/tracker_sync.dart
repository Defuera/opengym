import 'dart:async';

import 'package:flutter/foundation.dart';

import 'convex_client.dart';
import 'tracker_daily.dart';
import 'tracker_payload.dart';
import 'tracker_prefs.dart';
import 'tracker_source.dart';

/// What a sync did. Only the Trackers screen shows it; nothing else reacts.
enum SyncOutcome {
  /// Readings went to the server.
  sent,

  /// The phone had nothing to send in the window.
  nothing,

  /// Too soon after the last send, or one is running.
  skipped,

  /// The reading switch is off.
  off,

  /// No link to the server. Silent: the next sync tries again.
  offline,

  /// The phone says reading is not allowed.
  noPermission,

  /// No health store on this device.
  unavailable,

  /// Anything else went wrong. Silent: the next sync tries again.
  failed,
}

/// Reads the phone's health store and sends the last 14 days to the server
/// (ADR-036), for the coach. Runs only when the person turned reading on.
/// Never blocks the UI and never throws: every path ends in a [SyncOutcome].
class TrackerSync extends ChangeNotifier {
  TrackerSync({
    required this.source,
    required this.client,
    required this.prefs,
    required this.isConnected,
    DateTime Function()? now,
    this.interval = const Duration(minutes: 15),
    this.windowDays = 14,
  }) : _now = now ?? DateTime.now;

  final TrackerSource source;
  final ConvexClient client;
  final TrackerPrefs prefs;
  final bool Function() isConnected;
  final DateTime Function() _now;

  /// The least time between two automatic syncs.
  final Duration interval;

  /// How many days back each sync reads, today included.
  final int windowDays;

  TrackerPrefsState state = const TrackerPrefsState();
  bool busy = false;

  /// The outcome of the last run, for the screen.
  SyncOutcome? lastOutcome;

  Future<void> load() async {
    try {
      state = await prefs.load();
    } catch (_) {
      state = const TrackerPrefsState();
    }
    notifyListeners();
  }

  /// Turns reading on or off. On: asks the phone for read permission first;
  /// the switch stays off when there is no store or the dialog failed. Then
  /// sends at once. Off: sends nothing more (what the server holds stays).
  Future<void> setReadOn(bool on) async {
    if (on) {
      try {
        if (!await source.available()) {
          lastOutcome = SyncOutcome.unavailable;
          notifyListeners();
          return;
        }
        if (!await source.connect()) {
          lastOutcome = SyncOutcome.noPermission;
          notifyListeners();
          return;
        }
      } catch (_) {
        lastOutcome = SyncOutcome.failed;
        notifyListeners();
        return;
      }
    }
    await _save(state.copyWith(readOn: on));
    if (on) {
      unawaited(sync(force: true));
    } else {
      notifyListeners();
    }
  }

  /// One sync. [force] skips the interval (the button). Never throws.
  Future<SyncOutcome> sync({bool force = false}) async {
    if (!state.readOn) {
      return SyncOutcome.off;
    }
    final DateTime now = _now();
    final DateTime? last = state.lastSyncAt;
    if (busy || (!force && last != null && now.difference(last) < interval)) {
      return SyncOutcome.skipped;
    }
    if (!isConnected()) {
      return SyncOutcome.offline;
    }
    busy = true;
    notifyListeners();
    try {
      return lastOutcome = await _run(now);
    } catch (_) {
      return lastOutcome = SyncOutcome.failed;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<SyncOutcome> _run(DateTime now) async {
    if (!await source.available()) {
      return SyncOutcome.unavailable;
    }
    final DateTime today = DateTime(now.year, now.month, now.day);
    final TrackerSnapshot snap;
    try {
      snap = await source.read(from: DateTime(today.year, today.month, today.day - (windowDays - 1)), to: now);
    } on TrackerPermissionException {
      return SyncOutcome.noPermission;
    }
    // Belt and braces: the source drops workouts Gym Days wrote, and so do we.
    final List<TrackerWorkout> workouts =
        snap.workouts.where((TrackerWorkout w) => !isOwnSource(w.sourceId)).take(trackerWorkoutsMax).toList();
    final List<TrackerDay> days = snap.days.take(trackerDaysMax).toList();
    if (days.isNotEmpty || workouts.isNotEmpty) {
      await client.syncTracker(days: days, workouts: workouts);
    }
    await _save(state.copyWith(lastSyncAt: now, lastDays: days.length, lastWorkouts: workouts.length));
    return days.isEmpty && workouts.isEmpty ? SyncOutcome.nothing : SyncOutcome.sent;
  }

  Future<void> _save(TrackerPrefsState next) async {
    state = next;
    try {
      await prefs.save(next);
    } catch (_) {
      // The choice still holds in memory; it is saved on the next change.
    }
  }
}
