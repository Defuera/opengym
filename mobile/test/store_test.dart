import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/planner.dart';
import 'package:opengym/store.dart';

Future<AppStore> _newStore(InMemorySessionRepository repo) async {
  final AppStore store = AppStore(repo);
  await store.load();
  return store;
}

void main() {
  test('begin Push, complete the 4 bench sets, ready for next exercise', () async {
    final InMemorySessionRepository repo = InMemorySessionRepository();
    final AppStore store = await _newStore(repo);
    store.begin('Push');

    expect(store.active, isNotNull);
    expect(store.active!.exercises.length, 4);
    expect(store.currentExercise!.name, 'Bench press');
    expect(store.currentExercise!.sets.length, 4);

    for (int i = 0; i < 4; i++) {
      expect(store.curSet, i);
      store.completeSet();
    }
    final Exercise bench = store.currentExercise!;
    expect(allDone(bench), isTrue);
    expect(bench.sets.every((SetEntry s) => s.done && s.at != null), isTrue);
    // Bench press is not a fresh exercise, so nothing was carried over.
    expect(bench.sets.map((SetEntry s) => s.kg).toList(), <double>[20, 40, 60, 60]);

    store.nextExercise();
    expect(store.curEx, 1);
    expect(store.curSet, 0);
    expect(store.currentExercise!.name, 'Overhead press');
    expect(allDone(store.currentExercise!), isFalse);

    // The in-progress session was saved on every change.
    expect(repo.state.active, isNotNull);
    expect(repo.state.active!.exercises.first.sets.every((SetEntry s) => s.done), isTrue);
  });

  test('a first-time exercise carries the completed set to open sets', () async {
    final AppStore store = await _newStore(InMemorySessionRepository());
    store.begin('Push');
    store.nextExercise();
    final Exercise ex = store.currentExercise!;
    expect(ex.fresh, isTrue);
    expect(ex.carry, isTrue);

    store.changeReps(2);
    store.changeKg(2.5);
    store.completeSet();

    expect(ex.sets[0].done, isTrue);
    expect(ex.sets[0].reps, 10);
    expect(ex.sets[1].reps, 10);
    expect(ex.sets[1].kg, 2.5);
    expect(ex.sets[2].kg, 2.5);
    expect(ex.sets[1].done, isFalse);
    expect(ex.fresh, isFalse);
    expect(store.curSet, 1);
  });

  test('finish drops undone sets and empty exercises', () async {
    final InMemorySessionRepository repo = InMemorySessionRepository();
    final AppStore store = await _newStore(repo);
    store.begin('Push');
    store.completeSet();
    store.completeSet();
    store.finish();

    expect(store.active, isNull);
    expect(store.sessions.length, 1);
    final Session s = store.sessions.first;
    expect(s.endedAt, isNotNull);
    expect(s.exercises.length, 1);
    expect(s.exercises.first.name, 'Bench press');
    expect(s.exercises.first.sets.length, 2);
    expect(repo.state.sessions.length, 1);
    expect(repo.state.active, isNull);
  });

  test('finish with nothing done saves no session', () async {
    final InMemorySessionRepository repo = InMemorySessionRepository();
    final AppStore store = await _newStore(repo);
    store.begin('Pull');
    store.finish();
    expect(store.sessions, isEmpty);
    expect(repo.state.sessions, isEmpty);
    expect(repo.state.active, isNull);
  });

  test('discard saves nothing', () async {
    final InMemorySessionRepository repo = InMemorySessionRepository();
    final AppStore store = await _newStore(repo);
    store.begin('Push');
    store.completeSet();
    store.discard();

    expect(store.active, isNull);
    expect(store.sessions, isEmpty);
    expect(repo.state.sessions, isEmpty);
    expect(repo.state.active, isNull);
  });

  test('a saved session survives a reload', () async {
    final InMemorySessionRepository repo = InMemorySessionRepository();
    final AppStore first = await _newStore(repo);
    first.begin('Push');
    first.completeSet();

    final AppStore second = await _newStore(repo);
    expect(second.active, isNotNull);
    expect(second.active!.type, 'Push');
    expect(second.active!.exercises.first.sets.first.done, isTrue);
  });
}
