import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/data/session_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/store.dart';
import 'support/plans.dart';

/// Which exercise the session screen opens on when the person comes back to an open session.
Session _session({required int doneUpTo, int? partial}) {
  final List<Exercise> list = pushPlan();
  for (int i = 0; i < list.length; i++) {
    for (final SetEntry s in list[i].sets) {
      s.done = i < doneUpTo || i == partial;
    }
  }
  return Session(id: 's1', kind: 'gym', type: 'Gym', startedAt: 1000, exercises: list);
}

Future<AppStore> _open(Session s, {String? remembered}) async {
  final AppStore store = AppStore(InMemorySessionRepository(StoredState(sessions: <Session>[], active: s, activeExerciseId: remembered)));
  await store.load();
  return store;
}

void main() {
  test('sets done on exercises 1 and 2: it opens exercise 3', () async {
    final AppStore store = await _open(_session(doneUpTo: 2));
    expect(store.curEx, 2);
    store.resume();
    expect(store.curEx, 2);
  });

  test('all done: it opens the last exercise', () async {
    final AppStore store = await _open(_session(doneUpTo: 4));
    expect(store.curEx, 3);
  });

  test('the remembered exercise wins', () async {
    final Session s = _session(doneUpTo: 2);
    final AppStore store = await _open(s, remembered: s.exercises[0].id);
    expect(store.curEx, 0);
  });

  test('a removed remembered exercise falls back to the first with a set not done', () async {
    final AppStore store = await _open(_session(doneUpTo: 2), remembered: 'gone');
    expect(store.curEx, 2);
  });

  test('a new session opens the first exercise', () async {
    final AppStore store = await _open(_session(doneUpTo: 0));
    expect(store.curEx, 0);
    final AppStore fresh = AppStore(InMemorySessionRepository());
    await fresh.load();
    fresh.begin(prepared: pushPlan());
    expect(fresh.curEx, 0);
  });

  test('leaving on an exercise and coming back (also after a restart) opens that exercise', () async {
    final InMemorySessionRepository repo = InMemorySessionRepository();
    final AppStore store = AppStore(repo);
    await store.load();
    store.begin(prepared: pushPlan());
    store.completeSet();
    store.pickExercise(1);
    store.pickExercise(3);
    store.pickExercise(1);
    store.resume();
    expect(store.curEx, 1);
    final AppStore again = AppStore(repo);
    await again.load();
    expect(again.curEx, 1);
  });
}
