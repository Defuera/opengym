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

  void begin(String type) {
    if (active == null) {
      active = Session(
        id: newId(),
        kind: 'gym',
        type: type,
        startedAt: DateTime.now().millisecondsSinceEpoch,
        exercises: planFor(sessions, type),
      );
      _select(0);
      _commit();
      return;
    }
    // One session at a time: an open session of another type is resumed.
    _select(0);
    notifyListeners();
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
                done: true,
                at: s.at,
              ))
          .toList();
      if (done.isNotEmpty) {
        kept.add(Exercise(id: e.id, name: e.name, sets: done));
      }
    }
    a.exercises = kept;
    if (kept.isNotEmpty) {
      a.endedAt = DateTime.now().millisecondsSinceEpoch;
      sessions.add(a);
    }
    active = null;
    _select(0);
    _commit();
  }

  void discard() {
    active = null;
    _select(0);
    _commit();
  }

  void logActivity(String type, int minutes) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    sessions.add(Session(
      id: newId(),
      kind: 'activity',
      type: type,
      startedAt: now - minutes * 60000,
      endedAt: now,
      minutes: minutes,
    ));
    _commit();
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

  void moveExerciseEarlier(int v) {
    final Session? a = active;
    if (a == null || v <= 0 || v >= a.exercises.length) {
      return;
    }
    final String? id = currentExercise?.id;
    final List<Exercise> list = a.exercises;
    final Exercise t = list[v - 1];
    list[v - 1] = list[v];
    list[v] = t;
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

  void addExercise(String name) {
    final Session? a = active;
    if (a == null) {
      return;
    }
    a.exercises.add(makeExercise(sessions, name));
    _select(a.exercises.length - 1);
    _commit();
  }

  void swapExercise(String name) {
    final Session? a = active;
    if (a == null || currentExercise == null) {
      return;
    }
    a.exercises[curEx] = makeExercise(sessions, name);
    _select(curEx);
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

  void addSet() {
    final Exercise? e = currentExercise;
    if (e == null) {
      return;
    }
    final int reps = e.sets.isEmpty ? 8 : e.sets.last.reps;
    final double kg = e.sets.isEmpty ? 0.0 : e.sets.last.kg;
    e.sets.add(SetEntry(reps: reps, kg: kg));
    curSet = e.sets.length - 1;
    _commit();
  }

  void removeSet() {
    final Exercise? e = currentExercise;
    if (e == null || e.sets.length <= 1 || curSet < 0 || curSet >= e.sets.length) {
      return;
    }
    e.sets.removeAt(curSet);
    curSet = firstOpen(e);
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
