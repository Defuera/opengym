import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'data/session_repository.dart';
import 'models.dart';
import 'planner.dart';

/// Single app store. Storage is behind [SessionRepository]; the in-progress
/// session is saved on every change.
class AppStore extends ChangeNotifier {
  AppStore(this._repo);

  final SessionRepository _repo;

  /// Called with the session id after a session was saved locally (finished
  /// gym session or logged activity). Compose wires this to the outbox.
  void Function(String id)? onSessionSaved;

  /// Called with the session id after a session was removed locally.
  void Function(String id)? onSessionRemoved;

  List<Session> sessions = <Session>[];
  Session? active;
  int activeAt = 0;

  /// UI indices for the session screen.
  int curEx = 0;
  int curSet = 0;

  Future<void> load() async {
    final StoredState s = await _repo.load();
    sessions = List<Session>.from(s.sessions);
    active = s.active;
    activeAt = s.activeAt;
    _select(0);
  }

  void _commit() {
    activeAt = DateTime.now().millisecondsSinceEpoch;
    _repo.save(StoredState(
      sessions: sessions,
      active: active,
      activeAt: activeAt,
    ));
    notifyListeners();
  }

  Exercise? get currentExercise {
    final Session? a = active;
    if (a == null || curEx < 0 || curEx >= a.exercises.length) {
      return null;
    }
    return a.exercises[curEx];
  }

  SetEntry? get currentSet {
    final Exercise? e = currentExercise;
    if (e == null || curSet < 0 || curSet >= e.sets.length) {
      return null;
    }
    return e.sets[curSet];
  }

  void _select(int i) {
    curEx = i < 0 ? 0 : i;
    curSet = firstOpen(currentExercise);
  }

  // ---------- session lifecycle ----------

  void resume() {
    final Session? a = active;
    if (a == null) {
      return;
    }
    _select(math.min(curEx, a.exercises.length - 1));
    notifyListeners();
  }

  /// Starts a session with sets for [activity] (any name, default Gym) and
  /// the advised or chosen [focus] (null: none). [prepared] (e.g. from a
  /// server plan) replaces the local fallback plan (the user's last session
  /// of that activity and focus, else empty); [rationale] is shown on the
  /// session screen.
  void begin({
    String activity = gymType,
    String? focus,
    List<Exercise>? prepared,
    String? rationale,
  }) {
    // An open session with no done set holds nothing the user logged: a new
    // start replaces it. With a done set it is resumed, so work is never lost.
    if (active == null || !hasDoneSet) {
      final String name = activity.trim().isEmpty ? gymType : activity.trim();
      active = Session(
        id: newId(),
        kind: 'gym',
        type: name.length > 40 ? name.substring(0, 40).trim() : name,
        focus: focus,
        startedAt: DateTime.now().millisecondsSinceEpoch,
        exercises: prepared ?? planFor(sessions, name, focus),
        planNote: (rationale == null || rationale.isEmpty) ? null : rationale,
      );
      _select(0);
      _commit();
      return;
    }
    // One session at a time: an open session with logged sets is resumed.
    _select(0);
    notifyListeners();
  }

  /// Whether any set of the open session is done.
  bool get hasDoneSet {
    return active?.exercises.any((Exercise e) => e.sets.any((SetEntry s) => s.done)) ?? false;
  }

  void finish() {
    final Session? a = active;
    if (a == null) {
      return;
    }
    final List<Exercise> kept = <Exercise>[];
    for (final Exercise e in a.exercises) {
      final List<SetEntry> done = e.sets
          .where((SetEntry s) => s.done)
          .map((SetEntry s) => SetEntry(
                reps: s.reps,
                kg: s.kg,
                isMax: s.isMax,
                failed: s.failed,
                done: true,
                at: s.at,
                minutes: s.minutes,
                distanceKm: s.distanceKm,
              ))
          .toList();
      if (done.isNotEmpty) {
        kept.add(Exercise(id: e.id, name: e.name, measure: e.measure, sets: done));
      }
    }
    a.exercises = kept;
    String? savedId;
    if (kept.isNotEmpty) {
      a.endedAt = DateTime.now().millisecondsSinceEpoch;
      sessions.add(a);
      savedId = a.id;
    }
    active = null;
    _select(0);
    _commit();
    _announce(savedId);
  }

  void _announce(String? id) {
    final void Function(String id)? cb = onSessionSaved;
    if (id != null && cb != null) {
      cb(id);
    }
  }

  Session? sessionById(String id) {
    for (final Session s in sessions) {
      if (s.id == id) {
        return s;
      }
    }
    return null;
  }

  /// Merges the server's sessions (a live subscription) into the local log.
  ///
  /// The server's copy replaces the local one only when its content differs.
  /// Ids in [pending] have a write waiting in the outbox: the local copy wins
  /// for those, so a subscription update never undoes a local change. Absence
  /// from [remote] never deletes anything (the list is only the recent
  /// window). Returns how many sessions were added or changed.
  int mergeRemote(List<Session> remote, {Set<String> pending = const <String>{}}) {
    final Map<String, int> at = <String, int>{
      for (int i = 0; i < sessions.length; i++) sessions[i].id: i,
    };
    int changed = 0;
    for (final Session r in remote) {
      if (r.id.isEmpty || r.endedAt == null || pending.contains(r.id)) {
        continue;
      }
      final int? i = at[r.id];
      if (i == null) {
        at[r.id] = sessions.length;
        sessions.add(r);
        changed++;
      } else if (_sameFacts(sessions[i], r)) {
        continue;
      } else {
        sessions[i] = r;
        changed++;
      }
    }
    if (changed > 0) {
      sessions.sort((Session a, Session b) => a.when.compareTo(b.when));
      _commit();
    }
    return changed;
  }

  static bool _sameFacts(Session a, Session b) =>
      jsonEncode(a.toContractJson()) == jsonEncode(b.toContractJson());

  /// Removes a finished session from the log and tells the outbox.
  void removeSession(String id) {
    final int before = sessions.length;
    sessions.removeWhere((Session s) => s.id == id);
    if (sessions.length == before) {
      return;
    }
    _commit();
    final void Function(String id)? cb = onSessionRemoved;
    if (cb != null) {
      cb(id);
    }
  }

  /// Drops sessions that came from an import that was undone.
  void removeImported(String importId) {
    final int before = sessions.length;
    sessions.removeWhere((Session s) => s.importId == importId);
    if (sessions.length != before) {
      _commit();
    }
  }

  void discard() {
    active = null;
    _select(0);
    _commit();
  }

  /// Logs a time/distance activity. [focus] is its session type ('Easy',
  /// 'Intervals'), if any; [distanceKm] and [note] are optional.
  void logActivity(
    String type,
    int minutes, {
    String? focus,
    double? distanceKm,
    String? note,
  }) {
    final String? f = focus?.trim();
    final String? n = note?.trim();
    final int now = DateTime.now().millisecondsSinceEpoch;
    final String id = newId();
    final String name = type.trim().isEmpty ? 'Activity' : type.trim();
    sessions.add(Session(
      id: id,
      kind: 'activity',
      type: name.length > 40 ? name.substring(0, 40).trim() : name,
      focus: (f == null || f.isEmpty) ? null : f,
      startedAt: now - minutes * 60000,
      endedAt: now,
      minutes: minutes,
      distanceKm: (distanceKm == null || distanceKm <= 0) ? null : distanceKm,
      note: (n == null || n.isEmpty) ? null : n,
    ));
    _commit();
    _announce(id);
  }

  // ---------- exercises ----------

  void pickExercise(int i) {
    _select(i);
    notifyListeners();
  }

  void nextExercise() {
    _select(curEx + 1);
    notifyListeners();
  }

  /// Moves exercise [from] to position [to] (final index in the new order).
  /// The selected exercise stays selected.
  void moveExercise(int from, int to) {
    final Session? a = active;
    if (a == null) {
      return;
    }
    final List<Exercise> list = a.exercises;
    if (from < 0 || from >= list.length || to < 0 || to >= list.length || from == to) {
      return;
    }
    final String? id = currentExercise?.id;
    list.insert(to, list.removeAt(from));
    final int k = list.indexWhere((Exercise e) => e.id == id);
    curEx = k < 0 ? 0 : k;
    _commit();
  }

  void discardExercise(int v) {
    final Session? a = active;
    if (a == null || v < 0 || v >= a.exercises.length) {
      return;
    }
    final String? keep = currentExercise?.id;
    final List<Exercise> list = a.exercises;
    list.removeAt(v);
    final int k = list.indexWhere((Exercise e) => e.id == keep);
    _select(k >= 0 ? k : math.min(v, list.length - 1));
    _commit();
  }

  /// Adds an exercise. A name from the log keeps the measure it had last
  /// time; for a new name [measure] says how it is tracked.
  void addExercise(String name, {String measure = measureSets}) {
    final Session? a = active;
    if (a == null) {
      return;
    }
    a.exercises.add(makeExercise(sessions, name, measure: measure));
    _select(a.exercises.length - 1);
    _commit();
  }

  // ---------- sets ----------

  void pickSet(int i) {
    curSet = i;
    notifyListeners();
  }

  void changeReps(int delta) {
    final Exercise? e = currentExercise;
    final SetEntry? s = currentSet;
    if (e == null || s == null) {
      return;
    }
    s.reps = math.max(0, s.reps + delta);
    e.fresh = false;
    _commit();
  }

  /// Time exercise: changes the minutes of the current entry (1 to 600).
  void changeMinutes(double delta) {
    final SetEntry? s = currentSet;
    if (s == null || !s.isTime) {
      return;
    }
    s.minutes = ((s.minutes ?? 0) + delta).clamp(1.0, 600.0).toDouble();
    _commit();
  }

  /// Time exercise: sets the distance of the current entry; null or 0 clears it.
  void setDistance(double? km) {
    final SetEntry? s = currentSet;
    if (s == null || !s.isTime) {
      return;
    }
    s.distanceKm = (km == null || km <= 0) ? null : km;
    _commit();
  }

  void changeKg(double delta) {
    final Exercise? e = currentExercise;
    final SetEntry? s = currentSet;
    if (e == null || s == null) {
      return;
    }
    final double next = ((s.kg + delta) * 10).round() / 10;
    s.kg = next < 0 ? 0.0 : next;
    e.fresh = false;
    _commit();
  }

  /// Marks (or clears) "one more rep was tried and not completed" on the
  /// current set. Shown as `6½×70`; the planner and the server keep the flag.
  void toggleFailed() {
    final SetEntry? s = currentSet;
    if (s == null) {
      return;
    }
    s.failed = !s.failed;
    _commit();
  }

  void addSet() {
    final Exercise? e = currentExercise;
    if (e == null) {
      return;
    }
    if (e.isTime) {
      final SetEntry? last = e.sets.isEmpty ? null : e.sets.last;
      e.sets.add(SetEntry.time(last?.minutes ?? defaultMinutes, distanceKm: last?.distanceKm));
      curSet = e.sets.length - 1;
      _commit();
      return;
    }
    final int reps = e.sets.isEmpty ? 8 : e.sets.last.reps;
    final double kg = e.sets.isEmpty ? 0.0 : e.sets.last.kg;
    e.sets.add(SetEntry(reps: reps, kg: kg));
    curSet = e.sets.length - 1;
    _commit();
  }

  /// Removes set [i]. The last remaining set cannot be removed.
  void removeSetAt(int i) {
    final Exercise? e = currentExercise;
    if (e == null || e.sets.length <= 1 || i < 0 || i >= e.sets.length) {
      return;
    }
    e.sets.removeAt(i);
    if (i == curSet) {
      curSet = firstOpen(e);
    } else if (i < curSet) {
      curSet -= 1;
    }
    _commit();
  }

  void completeSet() {
    final Exercise? e = currentExercise;
    final SetEntry? s = currentSet;
    if (e == null || s == null) {
      return;
    }
    s.done = true;
    s.at = DateTime.now().millisecondsSinceEpoch;
    e.fresh = false;
    if (e.carry) {
      for (final SetEntry x in e.sets) {
        if (!x.done) {
          x.reps = s.reps;
          x.kg = s.kg;
        }
      }
    }
    curSet = firstOpen(e);
    _commit();
  }
}
