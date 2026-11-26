import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'data/session_repository.dart';
import 'models.dart';
import 'planner.dart';
import 'stores/countdown_store.dart';
import 'widgets/time_format.dart';

/// Single app store. Storage is behind [SessionRepository]; the in-progress
/// session is saved on every change.
class AppStore extends ChangeNotifier {
  AppStore(this._repo, {CountdownStore? countdown}) : countdown = countdown ?? CountdownStore();

  final SessionRepository _repo;

  /// The countdown of a time entry in the running session. It lives here so it
  /// outlasts the session screen; see [startCountdown].
  final CountdownStore countdown;

  /// Called with the session id after a session was saved locally (finished
  /// gym session or logged activity). Compose wires this to the outbox.
  void Function(String id)? onSessionSaved;

  /// Called with the session id after an activity was logged as one text
  /// ([logText]). Compose wires this to the outbox (the same text is sent to
  /// the server, which reads it into the session).
  void Function(String id)? onTextLogged;

  /// Called with the session id after a finished session was changed locally.
  void Function(String id)? onSessionEdited;

  /// Called with the session id after a session was removed locally.
  void Function(String id)? onSessionRemoved;

  /// Called with the session id and the new place id (null: none) after the
  /// place of a finished session was changed locally.
  void Function(String id, String? placeId)? onSessionPlaceChanged;

  /// Called after the open session changed on the phone (also when it ended).
  /// Compose wires this to the open session sync.
  void Function()? onActiveChanged;

  List<Session> sessions = <Session>[];
  Session? active;
  int activeAt = 0;

  /// The server's revision the open session is based on, whether it has a
  /// change the server does not hold, and the id of an ended session that is
  /// still open on the server. See `data/open_session_sync.dart`.
  int activeRev = 0;
  bool activeDirty = false;
  String? pendingClear;
  String? _activeJson;
  String? _activeId;

  /// How long after its end a finished session can be opened again.
  static const Duration continueWindow = Duration(hours: 1);

  /// The session as it was open just before the last finish (with the sets
  /// that were not done), and the time of that finish. See [continueSession].
  Session? _undo;
  int _undoAt = 0;

  /// UI indices for the session screen.
  int curEx = 0;
  int curSet = 0;

  /// The id of the exercise the person is on, kept with the open session on the phone (not on the server).
  String? _leftOnId;

  Future<void> load() async {
    final StoredState s = await _repo.load();
    sessions = List<Session>.from(s.sessions);
    active = s.active;
    activeAt = s.activeAt;
    activeRev = s.activeRev;
    activeDirty = s.activeDirty;
    pendingClear = s.pendingClear;
    _undo = s.undo;
    _undoAt = s.undoAt;
    _activeJson = openSessionJson;
    _activeId = active?.id;
    _leftOnId = active == null ? null : s.activeExerciseId;
    _select(openIndex());
  }

  /// The open session as the server takes it (`commands/openSession:put`), as
  /// one JSON text; null when there is none.
  String? get openSessionJson {
    final Session? a = active;
    return a == null ? null : jsonEncode(openSessionWire(a));
  }

  void _commit() {
    _syncCountdown();
    activeAt = DateTime.now().millisecondsSinceEpoch;
    // The open session changed, started or ended: the server must hear of it.
    final String? now = openSessionJson;
    final bool changed = now != _activeJson;
    if (changed) {
      if (now == null) {
        pendingClear = _activeId;
        activeDirty = false;
        activeRev = 0;
      } else {
        pendingClear = null;
        activeDirty = true;
      }
      _activeJson = now;
      _activeId = active?.id;
    }
    _save();
    notifyListeners();
    if (changed) {
      onActiveChanged?.call();
    }
  }

  void _save() {
    _repo.save(StoredState(
      sessions: sessions,
      active: active,
      activeAt: activeAt,
      activeRev: activeRev,
      activeDirty: activeDirty,
      pendingClear: pendingClear,
      undo: _undo,
      undoAt: _undoAt,
      activeExerciseId: active == null ? null : _leftOnId,
    ));
  }

  /// The server holds the open session as [json] at revision [rev]. A change
  /// made on the phone since [json] was sent keeps the session marked as not sent.
  void markActiveSynced(String json, int rev) {
    activeRev = rev;
    if (json == _activeJson) {
      activeDirty = false;
    }
    _save();
  }

  /// The server no longer holds the ended session [id].
  void markCleared(String id) {
    if (pendingClear == id) {
      pendingClear = null;
      _save();
    }
  }

  /// The open session is not on the server (any more): it is sent again.
  void markActiveUnsent() {
    if (active != null && !activeDirty) {
      activeDirty = true;
      _save();
    }
  }

  /// Takes the server's copy of the open session (a change made outside the
  /// phone, or a session opened elsewhere). The caller checked that the phone
  /// holds no unsent change. With the same session open, only the plan parts
  /// change, so nothing the phone alone knows is lost.
  void applyRemoteActive(Session remote, int rev) {
    final Session? a = active;
    if (a != null && a.id == remote.id) {
      a
        ..exercises = remote.exercises
        ..focus = remote.focus
        ..planNote = remote.planNote
        ..placeId = remote.placeId;
    } else {
      active = remote;
    }
    activeRev = rev;
    activeDirty = false;
    pendingClear = null;
    _activeJson = openSessionJson;
    _activeId = active?.id;
    _select(math.min(curEx, math.max(0, active!.exercises.length - 1)));
    _syncCountdown();
    activeAt = DateTime.now().millisecondsSinceEpoch;
    _save();
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
    _leftOnId = currentExercise?.id;
  }

  /// The exercise the session screen opens on: the one the person was on, if it
  /// is still there; else the first exercise with a set not done (the first one
  /// for a new session); else, when all is done, the last.
  int openIndex() {
    final List<Exercise> list = active?.exercises ?? <Exercise>[];
    if (list.isEmpty) {
      return 0;
    }
    final int left = list.indexWhere((Exercise e) => e.id == _leftOnId);
    if (_leftOnId != null && left >= 0) {
      return left;
    }
    final int open = list.indexWhere((Exercise e) => e.sets.any((SetEntry s) => !s.done));
    return open >= 0 ? open : list.length - 1;
  }

  // ---------- session lifecycle ----------

  void resume() {
    final Session? a = active;
    if (a == null) {
      return;
    }
    _select(openIndex());
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
    String? placeId,
    ProgramLink? program,
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
        placeId: placeId,
        program: program,
      );
      _select(0);
      _commit();
      return;
    }
    // One session at a time: an open session with logged sets is resumed.
    _select(openIndex());
    notifyListeners();
  }

  /// Whether any set of the open session is done.
  bool get hasDoneSet {
    return active?.exercises.any((Exercise e) => e.sets.any((SetEntry s) => s.done)) ?? false;
  }

  /// Ends the open session. Returns the id of the saved session, or null when
  /// nothing was saved (no done set).
  String? finish() {
    final Session? a = active;
    if (a == null) {
      return null;
    }
    // The session as it is now, with the open sets: "Continue session" brings it back.
    final Session before = Session.fromJson(a.toJson());
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
        kept.add(Exercise(id: e.id, name: e.name, measure: e.measure, sets: done, comment: e.comment));
      }
    }
    a.exercises = kept;
    String? savedId;
    if (kept.isNotEmpty) {
      a.endedAt = DateTime.now().millisecondsSinceEpoch;
      // A continued session is in the log already: the new end replaces it.
      sessions.removeWhere((Session s) => s.id == a.id);
      sessions.add(a);
      savedId = a.id;
      _undo = before;
      _undoAt = a.endedAt!;
    }
    active = null;
    _select(0);
    _commit();
    _announce(savedId);
    return savedId;
  }

  /// True when the finished session [id] can be opened again: it was finished
  /// on this phone less than [continueWindow] ago, was not changed since, and
  /// no other session with logged sets is open.
  bool canContinue(String id, {int? now}) {
    final Session? u = _undo;
    if (u == null || u.id != id || sessionById(id) == null) {
      return false;
    }
    if (active != null && hasDoneSet) {
      return false;
    }
    final int t = now ?? DateTime.now().millisecondsSinceEpoch;
    return t - _undoAt <= continueWindow.inMilliseconds;
  }

  /// Opens the finished session [id] again as it was before the finish, with
  /// its done sets and the sets that were not done. The finished copy stays in
  /// the log until the session is finished again; that end then replaces it.
  /// So a discard of the continued session loses nothing. False when
  /// [canContinue] is false.
  bool continueSession(String id) {
    if (!canContinue(id)) {
      return false;
    }
    final Session s = _undo!;
    _undo = null;
    active = s;
    int open = s.exercises.indexWhere((Exercise e) => e.sets.any((SetEntry x) => !x.done));
    _select(open < 0 ? math.max(0, s.exercises.length - 1) : open);
    _commit();
    return true;
  }

  /// A change to the finished session [id] ends the chance to continue it: the
  /// copy from before the finish no longer matches the log.
  void _dropUndo(String id) {
    if (_undo?.id == id) {
      _undo = null;
    }
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
      // A continued session is open again: the server's finished copy does not replace the log entry while it runs.
      if (r.id.isEmpty || r.endedAt == null || pending.contains(r.id) || r.id == active?.id) {
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

  /// The program link is left out: the server may not echo it, and the local copy keeps it.
  static bool _sameFacts(Session a, Session b) => a.parse == b.parse && _facts(a) == _facts(b);

  static String _facts(Session s) {
    final Map<String, dynamic> m = s.toContractJson();
    m.removeWhere((String k, Object? _) => k.startsWith('program'));
    return jsonEncode(m);
  }

  /// Sets the place of the open session. It is saved with the session.
  void setActivePlace(String? placeId) {
    final Session? a = active;
    if (a == null || a.placeId == placeId) {
      return;
    }
    a.placeId = placeId;
    _commit();
  }

  /// Sets the place of a finished session and tells the outbox. The
  /// recap changes nothing else. An unknown id changes nothing.
  void setSessionPlace(String id, String? placeId) {
    final Session? s = sessionById(id);
    if (s == null || s.placeId == placeId) {
      return;
    }
    s.placeId = placeId;
    _commit();
    final void Function(String id, String? placeId)? cb = onSessionPlaceChanged;
    if (cb != null) {
      cb(id, placeId);
    }
  }

  /// Replaces a finished session by its corrected copy (same id) and tells the
  /// outbox. The open session, timers and rest clocks are not touched. An
  /// unknown id changes nothing.
  void updateSession(Session s) {
    final int i = sessions.indexWhere((Session x) => x.id == s.id);
    if (i < 0) {
      return;
    }
    s.parse = null; // the user's edit is final: the server drops a late reading of the text
    _dropUndo(s.id);
    sessions[i] = s;
    sessions.sort((Session a, Session b) => a.when.compareTo(b.when));
    _commit();
    final void Function(String id)? cb = onSessionEdited;
    if (cb != null) {
      cb(s.id);
    }
  }

  /// Removes a finished session from the log and tells the outbox.
  void removeSession(String id) {
    final int before = sessions.length;
    sessions.removeWhere((Session s) => s.id == id);
    if (sessions.length == before) {
      return;
    }
    _dropUndo(id);
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

  /// Logs an activity as one text (ADR-018). The session is saved at once with
  /// the text word for word as its note and `parse: pending`; the server then
  /// reads the text into minutes, distance and exercises and the session
  /// updates by itself. Returns the id, or null when [text] is blank.
  String? logText(String type, String text) {
    final String t = text.trim();
    if (t.isEmpty) {
      return null;
    }
    final String name = type.trim().isEmpty ? 'Activity' : type.trim();
    final int now = DateTime.now().millisecondsSinceEpoch;
    final String id = newId();
    sessions.add(Session(
      id: id,
      kind: 'activity',
      type: name.length > 40 ? name.substring(0, 40).trim() : name,
      startedAt: now,
      endedAt: now,
      note: t.length > maxLogTextLength ? t.substring(0, maxLogTextLength) : t,
      parse: 'pending',
    ));
    _commit();
    onTextLogged?.call(id);
    return id;
  }

  // ---------- exercises ----------

  void pickExercise(int i) {
    _select(i);
    _save(); // the exercise the person is on is kept for the next open
    notifyListeners();
  }

  void nextExercise() {
    _select(curEx + 1);
    _save();
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
    _leftOnId = currentExercise?.id;
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

  /// Adds an exercise right after the one that is open, and opens it. A name
  /// from the log keeps the measure it had last time; for a new name [measure]
  /// says how it is tracked.
  void addExercise(String name, {String measure = measureSets}) {
    final Session? a = active;
    if (a == null) {
      return;
    }
    final int at = a.exercises.isEmpty ? 0 : math.min(math.max(curEx, 0) + 1, a.exercises.length);
    a.exercises.insert(at, makeExercise(sessions, name, measure: measure));
    _select(at);
    _commit();
  }

  /// Sets what the person wrote about the open exercise (ADR-029). An empty text removes it.
  void setComment(String? text) {
    final Exercise? e = currentExercise;
    final String? next = cleanComment(text);
    if (e == null || e.comment == next) {
      return;
    }
    e.comment = next;
    _commit();
  }

  // ---------- countdown ----------

  /// Cancels the countdown when its entry is gone, done or changed in minutes.
  void _syncCountdown() {
    if (!countdown.active) {
      return;
    }
    for (final Exercise e in active?.exercises ?? <Exercise>[]) {
      for (final SetEntry s in e.sets) {
        if (countdown.isFor(s)) {
          if (s.done || s.minutes != countdown.startMinutes) {
            countdown.cancel();
          }
          return;
        }
      }
    }
    countdown.cancel();
  }

  /// Starts the countdown for entry [i] of the current time exercise. At zero
  /// the entry is completed the way the check mark does it.
  void startCountdown(int i) {
    final Exercise? e = currentExercise;
    if (e == null || !e.isTime || i < 0 || i >= e.sets.length) {
      return;
    }
    final SetEntry s = e.sets[i];
    if (s.done) {
      return;
    }
    countdown.start(s, s.minutes ?? 0, () => _completeEntry(e, s), title: e.name);
  }

  void _completeEntry(Exercise e, SetEntry s) {
    final int i = e.sets.indexOf(s);
    if (i < 0 || s.done) {
      return;
    }
    _completeIn(e, i, current: identical(e, currentExercise));
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

  /// Time exercise: one step of the minus or plus control on the current entry
  /// ([delta] counts steps, see [stepMinutes]: 5 s up to 2 minutes, else 1 minute).
  void changeMinutes(double delta) {
    final SetEntry? s = currentSet;
    if (s == null || !s.isTime) {
      return;
    }
    s.minutes = stepMinutes(s.minutes ?? 0, delta);
    _commit();
  }

  /// Time exercise: the person typed the time of the current entry, in minutes.
  void setMinutes(double minutes) {
    final SetEntry? s = currentSet;
    if (s == null || !s.isTime || minutes <= 0) {
      return;
    }
    s.minutes = minutes;
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

  /// The person typed the reps of the current set (0 to 999).
  void setReps(int reps) {
    final Exercise? e = currentExercise;
    final SetEntry? s = currentSet;
    if (e == null || s == null || reps < 0 || reps > 999) {
      return;
    }
    s.reps = reps;
    e.fresh = false;
    _commit();
  }

  /// The person typed the weight of the current set (0 is bodyweight, at most 1000, 2 decimals).
  /// The plus and minus step from this value, so 4 becomes 6.5 (no snapping).
  void setKg(double kg) {
    final Exercise? e = currentExercise;
    final SetEntry? s = currentSet;
    if (e == null || s == null || kg < 0 || kg > 1000) {
      return;
    }
    s.kg = (kg * 100).round() / 100;
    e.fresh = false;
    _commit();
  }

  void changeKg(double delta) {
    final Exercise? e = currentExercise;
    final SetEntry? s = currentSet;
    if (e == null || s == null) {
      return;
    }
    final double next = ((s.kg + delta) * 100).round() / 100;
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

  /// Completes the current set.
  void completeSet() => completeSetAt(curSet);

  /// Done sets are undone, open sets are completed (the check control).
  void toggleSet(int i) {
    final Exercise? e = currentExercise;
    if (e != null && i >= 0 && i < e.sets.length && e.sets[i].done) {
      uncompleteSet(i);
    } else {
      completeSetAt(i);
    }
  }

  /// Marks set [i] of the current exercise undone and makes it the current set.
  void uncompleteSet(int i) {
    final Exercise? e = currentExercise;
    if (e == null || i < 0 || i >= e.sets.length || !e.sets[i].done) {
      return;
    }
    e.sets[i]
      ..done = false
      ..at = null;
    curSet = i;
    _commit();
  }

  /// Completes set [i] of the current exercise (any open set, not only the
  /// current one), carries its numbers to the open sets, and moves the
  /// current set to the first open one.
  void completeSetAt(int i) {
    final Exercise? e = currentExercise;
    if (e == null || i < 0 || i >= e.sets.length || e.sets[i].done) {
      return;
    }
    _completeIn(e, i, current: true);
  }

  void _completeIn(Exercise e, int i, {required bool current}) {
    final SetEntry s = e.sets[i];
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
    if (current) {
      curSet = firstOpen(e);
    }
    _commit();
  }
}
