import 'dart:async';

import '../models.dart';
import 'tracker_prefs.dart';
import 'tracker_source.dart';
import 'tracker_write_mapping.dart';

/// What a write attempt did.
enum WriteOutcome { written, off, alreadyWritten, nothingToWrite, refused, failed }

/// Writes a finished session to the phone's health store, once per session id,
/// when the person turned "Write my sessions to Health" on (ADR-036). A
/// failure never reaches the caller and never holds up finishing a session.
/// Editing or deleting a session later does not touch the store.
class TrackerWriter {
  TrackerWriter({required this.source, required this.settings});

  final TrackerSource source;
  final TrackerSettings settings;

  bool get on => settings.state.writeOn;

  /// Turns writing on or off. On: asks for write permission first; stays off
  /// when the store is missing or the request failed. Returns the new state.
  Future<bool> setOn(bool value) async {
    if (value) {
      try {
        if (!await source.available() || !await source.connectWrite()) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }
    await settings.update((TrackerPrefsState s) => s.copyWith(writeOn: value));
    return value;
  }

  /// Writes [session] once. Never throws.
  Future<WriteOutcome> onSessionFinished(Session session) async {
    try {
      if (!on) {
        return WriteOutcome.off;
      }
      if (settings.state.writtenIds.contains(session.id)) {
        return WriteOutcome.alreadyWritten;
      }
      final WorkoutWrite? w = workoutWriteFor(session);
      if (w == null) {
        return WriteOutcome.nothingToWrite;
      }
      if (!await source.writeWorkout(w)) {
        return WriteOutcome.refused;
      }
      await settings.update((TrackerPrefsState s) => s.copyWith(writtenIds: <String>{...s.writtenIds, session.id}));
      return WriteOutcome.written;
    } catch (_) {
      return WriteOutcome.failed;
    }
  }
}
