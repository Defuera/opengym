import 'package:flutter_test/flutter_test.dart';
import 'support/plans.dart';
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
    store.begin(focus: 'Push', prepared: pushPlan());

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
    store.begin(focus: 'Push', prepared: pushPlan());
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
    store.begin(focus: 'Push', prepared: pushPlan());
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
    store.begin(focus: 'Push', prepared: pushPlan());
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
    first.begin(focus: 'Push', prepared: pushPlan());
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
    store.begin(focus: 'Push', prepared: pushPlan());
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
    store.begin(focus: 'Push', prepared: pushPlan());
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
    store.begin(focus: 'Push', prepared: pushPlan());
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

  test('begin makes a session of any activity; an open session with a done set is resumed', () async {
    final AppStore store = await _newStore(InMemorySessionRepository());
    store.sessions.add(Session(
      id: 'h1',
      kind: 'gym',
      type: 'Home',
      focus: 'Quick',
      startedAt: 1,
      endedAt: 2,
      exercises: <Exercise>[
        Exercise(id: 'e', name: 'Press-up', sets: <SetEntry>[SetEntry(reps: 12, kg: 0, done: true)]),
      ],
    ));
    store.begin(focus: 'Push', prepared: pushPlan());
    expect(store.active!.type, 'Gym');
    expect(store.active!.focus, 'Push');
    expect(store.hasDoneSet, isFalse);
    store.discard();

    store.begin(activity: ' Home ', focus: 'Quick');
    expect(store.active!.type, 'Home');
    expect(store.active!.exercises.single.name, 'Press-up'); // the user's own last session
    store.begin(activity: 'Other'); // no set done yet: the new start replaces it
    expect(store.active!.type, 'Other');
    store.begin(activity: 'Home', focus: 'Quick');
    expect(store.active!.type, 'Home');
    store.completeSet();
    store.begin(activity: 'Other'); // a set is done: the open session is resumed
    expect(store.active!.type, 'Home');
    expect(store.active!.exercises.single.name, 'Press-up');
  });

  test('a "Home" session round trips through finish, JSON and reload', () async {
    final InMemorySessionRepository repo = InMemorySessionRepository();
    final AppStore store = await _newStore(repo);
    store.begin(activity: 'Home', focus: 'Quick', prepared: <Exercise>[makeExercise(<Session>[], 'Press-up')]);
    store.completeSet();
    store.finish();
    final Session s = store.sessions.single;
    expect(s.type, 'Home');
    expect(s.kind, 'gym');
    expect(s.toContractJson()['type'], 'Home');
    expect(s.toContractJson()['exercises'], isNotEmpty);
    expect(Session.fromJson(s.toJson()).type, 'Home');
    final AppStore again = await _newStore(repo);
    expect(again.sessions.single.type, 'Home');
    expect(again.sessions.single.focus, 'Quick');
  });

  test('logText saves the text at once as a pending activity and tells the outbox', () async {
    final AppStore store = await _newStore(InMemorySessionRepository());
    final List<String> told = <String>[];
    store.onTextLogged = told.add;
    final String? id = store.logText(' Run ', '  45 min, 8 km  ');
    expect(id, isNotNull);
    expect(told, <String>[id!]);
    final Session s = store.sessions.single;
    expect(s.kind, 'activity');
    expect(s.type, 'Run');
    expect(s.note, '45 min, 8 km');
    expect(s.parse, 'pending');
    expect(s.exercises, isEmpty);
    expect(s.startedAt, s.endedAt);
    expect(store.logText('Run', '   '), isNull);
    expect(store.sessions, hasLength(1));
  });

  test('a user edit clears parse; the server copy with a result replaces the local one', () async {
    final AppStore store = await _newStore(InMemorySessionRepository());
    final String id = store.logText('Run', '45 min')!;
    final Session server = Session.fromJson(<String, dynamic>{
      ...store.sessions.single.toJson(),
      'minutes': 45,
      'parse': 'done',
    });
    expect(store.mergeRemote(<Session>[server]), 1);
    expect(store.sessionById(id)!.minutes, 45);
    expect(store.sessionById(id)!.parsePending, isFalse);
    final Session edit = Session.fromJson(<String, dynamic>{...server.toJson(), 'parse': 'pending'});
    store.updateSession(edit);
    expect(store.sessionById(id)!.parse, isNull);
  });

  test('a new exercise goes right after the open one and opens', () async {
    final AppStore store = await _newStore(InMemorySessionRepository());
    store.begin(focus: 'Push', prepared: pushPlan());
    final List<String> before = store.active!.exercises.map((Exercise e) => e.name).toList();
    store.pickExercise(1);
    store.addExercise('Rowing machine', measure: measureTime);
    expect(store.curEx, 2);
    expect(store.currentExercise!.name, 'Rowing machine');
    expect(store.active!.exercises.map((Exercise e) => e.name).toList(),
        <String>[before[0], before[1], 'Rowing machine', ...before.sublist(2)]);
    // In an empty session it is the first.
    final AppStore empty = await _newStore(InMemorySessionRepository());
    empty.begin(prepared: <Exercise>[]);
    empty.addExercise('Squat');
    expect(empty.curEx, 0);
    expect(empty.active!.exercises.single.name, 'Squat');
  });

  test('a typed time sets the minutes of the current time entry only', () async {
    final AppStore store = await _newStore(InMemorySessionRepository());
    store.begin(prepared: <Exercise>[]);
    store.addExercise('Rowing machine', measure: measureTime);
    store.setMinutes(2.5);
    expect(store.currentSet!.minutes, 2.5);
    store.addExercise('Squat');
    store.setMinutes(7);
    expect(store.currentSet!.minutes, isNull);
  });

  test('a comment on an exercise is kept through finish and goes to the server shape', () async {
    final AppStore store = await _newStore(InMemorySessionRepository());
    store.begin(focus: 'Push', prepared: pushPlan());
    store.setComment('  I feel my shoulder a bit  ');
    expect(store.currentExercise!.comment, 'I feel my shoulder a bit');
    expect(store.activeDirty, isTrue); // it goes to the open session on the server too
    store.completeSet();
    final String id = store.finish()!;
    final Session saved = store.sessionById(id)!;
    expect(saved.exercises.single.comment, 'I feel my shoulder a bit');
    expect((saved.toContractJson()['exercises'] as List<dynamic>).single['comment'], 'I feel my shoulder a bit');
    // It survives the phone's own storage and the server's answer.
    expect(Session.fromJson(saved.toJson()).exercises.single.comment, 'I feel my shoulder a bit');
  });

  test('an empty comment removes it; a long one is cut', () async {
    final AppStore store = await _newStore(InMemorySessionRepository());
    store.begin(focus: 'Push', prepared: pushPlan());
    store.setComment('note');
    store.setComment('   ');
    expect(store.currentExercise!.comment, isNull);
    expect(store.currentExercise!.toJson().containsKey('comment'), isFalse);
    store.setComment('x' * 1500);
    expect(store.currentExercise!.comment!.length, 1000);
  });

  group('continue a finished session', () {
    Future<(AppStore, InMemorySessionRepository, String)> finished() async {
      final InMemorySessionRepository repo = InMemorySessionRepository();
      final AppStore store = await _newStore(repo);
      store.begin(focus: 'Push', prepared: pushPlan());
      store.setComment('felt fine');
      store.completeSet();
      final String id = store.finish()!;
      return (store, repo, id);
    }

    test('it opens again as it was: done sets, open sets, every exercise', () async {
      final (AppStore store, _, String id) = await finished();
      expect(store.sessionById(id)!.exercises.length, 1); // the log keeps only what was done
      expect(store.canContinue(id), isTrue);
      expect(store.continueSession(id), isTrue);
      expect(store.active!.id, id);
      expect(store.active!.endedAt, isNull);
      expect(store.active!.exercises.length, 4);
      expect(store.active!.exercises.first.sets.map((SetEntry s) => s.done), <bool>[true, false, false, false]);
      expect(store.active!.exercises.first.comment, 'felt fine');
      expect(store.curEx, 0); // the first exercise with an open set
      expect(store.curSet, 1);
      expect(store.activeDirty, isTrue); // it goes to the server as the open session again
      expect(store.sessionById(id), isNotNull); // the finished copy stays until the new end
      expect(store.canContinue(id), isFalse); // once
    });

    test('the new end replaces the finished copy; nothing is doubled', () async {
      final (AppStore store, _, String id) = await finished();
      final List<String> saved = <String>[];
      store.onSessionSaved = saved.add;
      store.continueSession(id);
      store.completeSet();
      expect(store.finish(), id);
      expect(saved, <String>[id]);
      expect(store.sessions.where((Session s) => s.id == id).length, 1);
      expect(store.sessionById(id)!.exercises.first.sets.length, 2);
    });

    test('a discard of the continued session keeps the finished one', () async {
      final (AppStore store, _, String id) = await finished();
      store.continueSession(id);
      store.discard();
      expect(store.active, isNull);
      expect(store.sessionById(id)!.exercises.first.sets.length, 1);
    });

    test('not after one hour, not after an edit, not while other logged work is open', () async {
      final (AppStore store, _, String id) = await finished();
      final int now = DateTime.now().millisecondsSinceEpoch;
      expect(store.canContinue(id, now: now + 59 * 60000), isTrue);
      expect(store.canContinue(id, now: now + 61 * 60000), isFalse);
      expect(store.canContinue('other'), isFalse);
      store.begin(focus: 'Pull', prepared: pushPlan());
      expect(store.canContinue(id), isTrue); // a plan with no done set gives way
      store.completeSet();
      expect(store.canContinue(id), isFalse);
      store.discard();
      store.updateSession(Session.fromJson(store.sessionById(id)!.toJson()));
      expect(store.canContinue(id), isFalse);
    });

    test('the chance survives a restart of the app', () async {
      final (AppStore _, InMemorySessionRepository repo, String id) = await finished();
      final AppStore again = await _newStore(repo);
      expect(again.canContinue(id), isTrue);
      expect(again.continueSession(id), isTrue);
      expect(again.active!.exercises.length, 4);
    });

    test('the server copy of a continued session does not touch the log while it runs', () async {
      final (AppStore store, _, String id) = await finished();
      final Session server = Session.fromJson(<String, dynamic>{...store.sessionById(id)!.toJson(), 'note': 'from server'});
      store.continueSession(id);
      expect(store.mergeRemote(<Session>[server]), 0);
    });
  });
}
