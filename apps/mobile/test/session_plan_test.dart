import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/store.dart';
import 'package:opengym/stores/plan_store.dart';

import 'support/fake_convex_client.dart';

/// ADR-041: a finished session keeps the plan it started from.
Future<AppStore> _store() async {
  final AppStore s = AppStore(InMemorySessionRepository());
  await s.load();
  return s;
}

Plan _plan() => const Plan(
      id: 'p',
      focus: 'Push',
      createdAt: 1,
      source: 'ai',
      rationale: 'Push day, bench first.',
      exercises: <PlanExercise>[
        PlanExercise(name: 'Bench', note: 'Add 2.5 kg', sets: <PlanSet>[PlanSet(reps: 8, kg: 60), PlanSet(reps: 8, kg: 60)]),
        PlanExercise(name: 'Dips', sets: <PlanSet>[PlanSet(reps: 10, kg: 0)]),
        PlanExercise(name: 'Curl', sets: <PlanSet>[PlanSet(reps: 10, kg: 15)]),
        PlanExercise(name: 'Bike', measure: 'time', sets: <PlanSet>[PlanSet(reps: 0, kg: 0, minutes: 20)]),
      ],
    );

void main() {
  late PlanStore plans;
  setUp(() => plans = PlanStore(client: FakeConvexClient()));

  test('a planned exercise keeps its plan sets when the person edits the sets', () async {
    final AppStore store = await _store();
    store.begin(focus: 'Push', prepared: plans.exercisesFor(_plan()), rationale: 'Push day, bench first.');
    store.changeKg(5); // 65 kg on the first set
    final Exercise bench = store.currentExercise!;
    expect(bench.sets.first.kg, 65);
    expect(bench.planned!.map((SetEntry s) => '${s.reps}x${s.kg}').toList(), <String>['8x60.0', '8x60.0']);
  });

  test('finishing keeps planned next to done, the plan note, and lists the skipped exercises', () async {
    final AppStore store = await _store();
    store.begin(focus: 'Push', prepared: plans.exercisesFor(_plan()), rationale: 'Push day, bench first.');
    store.changeKg(5);
    store.completeSet(); // bench, set 1: 8x65 (plan: 8x60)
    store.nextExercise(); // Dips: left with no done set
    store.discardExercise(2); // Curl is removed by the person
    store.addExercise('Face pull'); // added, not planned
    store.completeSet();
    final String? id = store.finish();
    final Session s = store.sessionById(id!)!;

    expect(s.exercises.map((Exercise e) => e.name).toList(), <String>['Bench', 'Face pull']);
    expect(s.exercises.first.sets.map((SetEntry x) => x.kg).toList(), <double>[65]);
    expect(s.exercises.first.planned!.map((SetEntry x) => x.kg).toList(), <double>[60, 60]);
    expect(s.exercises.last.planned, isNull);
    expect(s.skipped!.map((SkippedExercise x) => x.name).toList(), <String>['Curl', 'Dips', 'Bike']);

    final Map<String, dynamic> j = s.toContractJson();
    expect(j['planNote'], 'Push day, bench first.');
    final List<dynamic> ex = j['exercises'] as List<dynamic>;
    expect((ex[0] as Map<String, dynamic>)['planned'], <Map<String, dynamic>>[
      <String, dynamic>{'reps': 8, 'kg': 60.0, 'max': false},
      <String, dynamic>{'reps': 8, 'kg': 60.0, 'max': false},
    ]);
    expect((ex[0] as Map<String, dynamic>)['planNote'], 'Add 2.5 kg');
    expect((ex[1] as Map<String, dynamic>).containsKey('planned'), isFalse);
    expect((j['skipped'] as List<dynamic>).map((dynamic x) => (x as Map<String, dynamic>)['name']).toList(), <String>['Curl', 'Dips', 'Bike']);
    final Map<String, dynamic> bike = (j['skipped'] as List<dynamic>).last as Map<String, dynamic>;
    expect(bike['measure'], 'time');
    expect(bike['planned'], <Map<String, dynamic>>[<String, dynamic>{'minutes': 20.0}]);
  });

  test('the saved shape reads back, so a corrected past session keeps its plan', () async {
    final AppStore store = await _store();
    store.begin(focus: 'Push', prepared: plans.exercisesFor(_plan()), rationale: 'Push day, bench first.');
    store.completeSet();
    final Session s = store.sessionById(store.finish()!)!;
    final Session again = Session.fromJson(s.toJson());
    expect(again.skipped!.length, 3);
    expect(again.exercises.first.planned!.length, 2);
    final Session fromServer = Session.fromJson(<String, dynamic>{...s.toContractJson(), 'exercises': <Map<String, dynamic>>[for (final Exercise e in s.exercises) e.toContractJson()]});
    expect(fromServer.exercises.first.note, 'Add 2.5 kg'); // the server's `planNote` is the note again
    expect(fromServer.planNote, 'Push day, bench first.');
  });

  test('a session with no plan has none and sends none', () async {
    final AppStore store = await _store();
    store.begin(focus: 'Push', prepared: <Exercise>[]);
    store.addExercise('Squat');
    store.completeSet();
    final Session s = store.sessionById(store.finish()!)!;
    expect(s.skipped, isNull);
    final Map<String, dynamic> j = s.toContractJson();
    expect(j.containsKey('planNote'), isFalse);
    expect(j.containsKey('skipped'), isFalse);
    expect((j['exercises'] as List<dynamic>).first as Map<String, dynamic>, isNot(contains('planned')));
  });

  test('continuing a finished session brings the plan back with it', () async {
    final AppStore store = await _store();
    store.begin(focus: 'Push', prepared: plans.exercisesFor(_plan()), rationale: 'Push day, bench first.');
    store.completeSet();
    final String id = store.finish()!;
    expect(store.continueSession(id), isTrue);
    expect(store.active!.exercises.length, 4);
    expect(store.active!.exercises.every((Exercise e) => e.planned != null), isTrue);
    expect(store.active!.skipped, isNull);
  });
}
