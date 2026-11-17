import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/planner.dart';
import 'support/fake_convex_client.dart';
import 'package:opengym/stores/plan_store.dart';
import 'package:opengym/store.dart';

Future<AppStore> _newStore(InMemorySessionRepository repo) async {
  final AppStore store = AppStore(repo);
  await store.load();
  return store;
}

void main() {
  _storeSetAndOrderTests();
  test('begin Push, complete the 4 bench sets, ready for next exercise', () async {
    final InMemorySessionRepository repo = InMemorySessionRepository();
    final AppStore store = await _newStore(repo);
    store.begin(focus: 'Push');

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
    store.begin(focus: 'Push');
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
    store.begin(focus: 'Push');
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
    store.begin(focus: 'Pull');
    store.finish();
    expect(store.sessions, isEmpty);
    expect(repo.state.sessions, isEmpty);
    expect(repo.state.active, isNull);
  });

  test('discard saves nothing', () async {
    final InMemorySessionRepository repo = InMemorySessionRepository();
    final AppStore store = await _newStore(repo);
    store.begin(focus: 'Push');
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
    first.begin(focus: 'Push');
    first.completeSet();

    final AppStore second = await _newStore(repo);
    expect(second.active, isNotNull);
    expect(second.active!.focus, 'Push');
    expect(second.active!.exercises.first.sets.first.done, isTrue);
  });

  test('begin with a prepared plan uses it instead of the local planner', () async {
    final AppStore store = await _newStore(InMemorySessionRepository());
    final PlanStore plans = PlanStore(client: FakeConvexClient());
    const Plan plan = Plan(
      id: 'p1',
      focus: 'Push',
      createdAt: 1,
      source: 'ai',
      rationale: 'Sample rationale.',
      exercises: <PlanExercise>[
        PlanExercise(
          name: 'Dips',
          note: 'Sample note',
          sets: <PlanSet>[PlanSet(reps: 8, kg: 0), PlanSet(reps: 8, kg: 0)],
        ),
      ],
    );

    store.begin(focus: 'Push', prepared: plans.exercisesFor(plan), rationale: plan.rationale);

    expect(store.active!.exercises.length, 1);
    expect(store.currentExercise!.name, 'Dips');
    expect(store.currentExercise!.note, 'Sample note');
    expect(store.currentExercise!.sets.length, 2);
    expect(store.currentExercise!.sets.every((SetEntry s) => !s.done), isTrue);
    expect(store.active!.planNote, 'Sample rationale.');
  });

  test('finishing a session announces its id once', () async {
    final AppStore store = await _newStore(InMemorySessionRepository());
    final List<String> seen = <String>[];
    store.onSessionSaved = seen.add;
    store.begin(focus: 'Push');
    store.completeSet();
    store.finish();
    expect(seen, <String>[store.sessions.first.id]);

    store.begin(focus: 'Pull');
    store.finish(); // nothing done, nothing saved
    expect(seen.length, 1);
  });
}

void _storeSetAndOrderTests() {
  test('removeSetAt removes one set, keeps selection, keeps the last set', () async {
    final AppStore store = await _newStore(InMemorySessionRepository());
    store.begin(focus: 'Push');
    expect(store.currentExercise!.sets.length, 4);
    store.pickSet(2);
    store.removeSetAt(0);
    expect(store.currentExercise!.sets.length, 3);
    expect(store.curSet, 1);
    store.removeSetAt(1);
    expect(store.currentExercise!.sets.length, 2);
    store.removeSetAt(0);
    expect(store.currentExercise!.sets.length, 1);
    store.removeSetAt(0);
    expect(store.currentExercise!.sets.length, 1);
  });

  test('moveExercise reorders and keeps the selected exercise', () async {
    final AppStore store = await _newStore(InMemorySessionRepository());
    store.begin(focus: 'Push');
    final List<String> before =
        store.active!.exercises.map((Exercise e) => e.name).toList();
    store.moveExercise(0, 2);
    final List<String> after = store.active!.exercises.map((Exercise e) => e.name).toList();
    expect(after, <String>[before[1], before[2], before[0], before[3]]);
    expect(store.currentExercise!.name, before[0]);
    expect(store.curEx, 2);
    store.moveExercise(2, 2);
    store.moveExercise(9, 0);
    expect(store.active!.exercises.map((Exercise e) => e.name).toList(), after);
  });

  test('begin makes a Gym session with the focus; changeFocus swaps the plan before the first set', () async {
    final AppStore store = await _newStore(InMemorySessionRepository());
    store.begin(focus: 'Push');
    expect(store.active!.type, 'Gym');
    expect(store.active!.focus, 'Push');
    expect(store.hasDoneSet, isFalse);
    store.changeFocus('Legs');
    expect(store.active!.focus, 'Legs');
    expect(store.active!.type, 'Gym');
    expect(store.active!.exercises.first.name, 'Squat');
    store.completeSet();
    final String firstName = store.active!.exercises.first.name;
    store.changeFocus('Pull'); // a set is done: only the label changes
    expect(store.active!.focus, 'Pull');
    expect(store.active!.exercises.first.name, firstName);
  });

  test('logActivity keeps the session type as focus; blank means none', () async {
    final AppStore store = await _newStore(InMemorySessionRepository());
    store.logActivity('Run', 30, focus: ' Intervals ');
    store.logActivity('Run', 20, focus: '  ');
    expect(store.sessions[0].focus, 'Intervals');
    expect(store.sessions[1].focus, isNull);
    expect(store.sessions[0].type, 'Run');
  });
}
