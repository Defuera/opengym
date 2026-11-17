import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';
import 'package:opengym/stores/dashboard_store.dart';
import 'package:opengym/stores/import_store.dart';
import 'package:opengym/stores/plan_store.dart';
import 'package:opengym/stores/review_store.dart';

import 'support/fake_convex_client.dart';

const Prediction _pull = Prediction(kind: 'gym', type: 'Gym', focus: 'Pull', reason: 'Due');

void main() {
  test('predictions are pushed to the store, rules first, AI later', () async {
    final FakeConvexClient fake = FakeConvexClient();
    final PlanStore plans = PlanStore(client: fake)..start();
    fake.predictions.set(const Stored<List<Prediction>>(<Prediction>[_pull], stored: false));
    await pump();
    expect(plans.remote.single.focus, 'Pull');
    expect(plans.source, 'rules');
    fake.predictions.set(const Stored<List<Prediction>>(
        <Prediction>[Prediction(kind: 'gym', type: 'Gym', focus: 'Legs')],
        stored: true, source: 'ai'));
    await pump();
    expect(plans.remote.single.focus, 'Legs');
    expect(plans.source, 'ai');
    plans.dispose();
  });

  test('the plan for a focus comes from the live plan query', () async {
    final FakeConvexClient fake = FakeConvexClient();
    final PlanStore plans = PlanStore(client: fake);
    const Plan plan = Plan(
      id: 'rules:Upper',
      focus: 'Upper',
      createdAt: 1,
      source: 'rules',
      rationale: 'r',
      exercises: <PlanExercise>[
        PlanExercise(name: 'Row', sets: <PlanSet>[PlanSet(reps: 8, kg: 40)]),
      ],
    );
    fake.plans['Upper'] = Live<Stored<Plan>>(const Stored<Plan>(plan, stored: false));
    expect((await plans.fetchNext(focus: 'Upper'))!.exercises.single.name, 'Row');
    // No answer in time: null, so the caller uses the local planner.
    final PlanStore slow = PlanStore(client: fake, planBudget: const Duration(milliseconds: 20));
    expect(await slow.fetchNext(focus: 'Lower'), isNull);
  });

  test('the dashboard follows the selected period and updates live', () async {
    final FakeConvexClient fake = FakeConvexClient();
    final DashboardStore d = DashboardStore(client: fake)..select(7);
    fake.dashboards[7]!.set(const Stored<Dashboard>(
        Dashboard(days: 7, source: 'rules', modules: <DashboardModule>[]),
        stored: false));
    await pump();
    expect(d.current!.source, 'rules');
    fake.dashboards[7]!.set(const Stored<Dashboard>(
        Dashboard(days: 7, source: 'ai', modules: <DashboardModule>[]),
        stored: true,
        source: 'ai'));
    await pump();
    expect(d.current!.source, 'ai');
    d.select(30);
    expect(d.current, isNull); // the 7-day result is not shown for 30 days
    fake.dashboards[30]!.set(const Stored<Dashboard>(
        Dashboard(days: 30, source: 'rules', modules: <DashboardModule>[]),
        stored: false));
    await pump();
    expect(d.current!.days, 30);
    d.dispose();
  });

  test('the review appears when the session is on the server, then upgrades', () async {
    final FakeConvexClient fake = FakeConvexClient();
    final ReviewStore r = ReviewStore(client: fake)..watch('s1');
    fake.reviews['s1']!.set(const Stored<Review?>(null, stored: false));
    await pump();
    expect(r.current, isNull);
    fake.reviews['s1']!.set(const Stored<Review?>(
        Review(sessionId: 's1', source: 'rules', summary: 'Good'),
        stored: false));
    await pump();
    expect(r.current!.source, 'rules');
    fake.reviews['s1']!.set(const Stored<Review?>(
        Review(sessionId: 's1', source: 'ai', summary: 'Better'),
        stored: true,
        source: 'ai'));
    await pump();
    expect(r.current!.summary, 'Better');
    r.dismiss();
    expect(r.current, isNull);
  });

  test('past imports are live and undo goes through the gateway', () async {
    final FakeConvexClient fake = FakeConvexClient();
    final ImportStore s = ImportStore(client: fake)..watchPast();
    String? undone;
    s.onUndone = (String id) => undone = id;
    fake.serverChanged(() => fake.serverImports['i1'] = const ImportJob(
        id: 'i1',
        status: 'done',
        total: 1,
        processed: 1,
        counts: ImportCounts(sessions: 3),
        notes: <String>[],
        createdAt: 1));
    await pump();
    expect(s.past.single.id, 'i1');
    expect(await s.undo('i1'), isTrue);
    expect(undone, 'i1');
    expect(fake.calls, contains('removeImport:i1'));
    await pump();
    expect(s.past, isEmpty);
    s.dispose();
  });
}
