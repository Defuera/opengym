import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/other_activity_screen.dart';
import 'package:opengym/screens/session_screen.dart';
import 'support/fake_convex_client.dart';
import 'support/sheet_fixtures.dart';

void main() {
  testWidgets('Home has Start session and Log, and no old start screen', (WidgetTester t) async {
    await openHome(t);
    expect(find.text('Start session'), findsOneWidget);
    expect(find.text('Log'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('Start sheet lists stored proposals; a tap opens the stored plan', (WidgetTester t) async {
    final (FakeConvexClient fake0, AppDeps d) = await openHome(t);
    await openStart(t);
    expect(find.text('Gym · Upper'), findsOneWidget);
    expect(find.text('Home · Quick'), findsOneWidget);
    expect(find.text('Last upper session was 13 Nov'), findsOneWidget);
    expect(find.text('Something new: "hotel gym, 30 min"'), findsOneWidget);
    expect(find.text('Start empty, without a plan ›'), findsOneWidget);
    await t.tap(find.text('Gym · Upper'));
    await t.pumpAndSettle();
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(d.store.active!.type, 'Gym');
    expect(d.store.active!.focus, 'Upper');
    expect(d.store.active!.exercises.single.name, 'Stored row');
  });

  testWidgets('a proposal of another activity opens that activity', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    fake.plans[FakeConvexClient.planKey(activity: 'Home', focus: 'Quick')] = Live<Stored<Plan>>(
        const Stored<Plan>(
            Plan(
              id: 'h',
              focus: 'Quick',
              createdAt: 1,
              source: 'ai',
              rationale: '',
              exercises: <PlanExercise>[
                PlanExercise(name: 'Burpee', sets: <PlanSet>[PlanSet(reps: 10, kg: 0)]),
              ],
            ),
            stored: true));
    await openStart(t);
    await t.tap(find.text('Home · Quick'));
    await t.pumpAndSettle();
    expect(d.store.active!.type, 'Home');
    expect(d.store.active!.exercises.single.name, 'Burpee');
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('Something new, ready: opens the prepared session under the proposed name',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    await openStart(t);
    await typeAndPrepare(t, 'hotel gym, 30 min');
    expect(find.text('Preparing…'), findsOneWidget);
    expect(find.text('Start empty now'), findsOneWidget);
    expect(fake.startSent.single.$2, 'hotel gym, 30 min');
    expect(fake.calls.where((String c) => c.startsWith('saveSession')), isEmpty);
    fake.answerStart(StartRequest(
      requestId: fake.lastStartId,
      status: 'ready',
      proposal: const StartProposal(
        kind: 'gym',
        type: 'Hotel gym',
        focus: 'Full body',
        reason: 'r',
        plan: Plan(
          id: 'x',
          focus: 'Full body',
          createdAt: 1,
          source: 'ai',
          rationale: 'Short and simple',
          exercises: <PlanExercise>[
            PlanExercise(name: 'Goblet squat', sets: <PlanSet>[PlanSet(reps: 10, kg: 12)]),
          ],
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(d.store.active!.type, 'Hotel gym');
    expect(d.store.active!.focus, 'Full body');
    expect(d.store.active!.exercises.single.name, 'Goblet squat');
    expect(d.store.active!.planNote, 'Short and simple');
  });

  testWidgets('Something new, ready as an activity: opens the log form filled in',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps _) = await openHome(t);
    await openStart(t);
    await typeAndPrepare(t, 'padel');
    fake.answerStart(StartRequest(
      requestId: fake.lastStartId,
      status: 'ready',
      proposal: const StartProposal(kind: 'activity', type: 'Padel', focus: 'Doubles', minutes: 60),
    ));
    await t.pumpAndSettle();
    expect(find.byType(OtherActivityScreen), findsOneWidget);
    expect(find.text('Padel'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Doubles'), findsOneWidget);
  });

  testWidgets('Something new, failed: an empty session named from the text', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    await openStart(t);
    await typeAndPrepare(t, 'hotel gym, 30 min');
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'failed'));
    await t.pumpAndSettle();
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(d.store.active!.type, 'Hotel gym');
    expect(d.store.active!.exercises, isEmpty);
  });

  testWidgets('Something new, no answer in 20 s: an empty session', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await openHome(t);
    await openStart(t);
    await typeAndPrepare(t, 'hotel gym, 30 min');
    await t.pump(const Duration(seconds: 19));
    expect(find.text('Preparing…'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(d.store.active!.type, 'Hotel gym');
    expect(d.store.active!.exercises, isEmpty);
  });

  testWidgets('Something new, request error: an empty session', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    fake.failNext = const ConvexCallException('nope');
    await openStart(t);
    await typeAndPrepare(t, 'swim');
    await t.pumpAndSettle();
    expect(d.store.active!.type, 'Swim');
  });

  testWidgets('Start empty now skips the wait; a late answer opens nothing', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    await openStart(t);
    await typeAndPrepare(t, 'x' * 60);
    await t.tap(find.text('Start empty now'));
    await t.pumpAndSettle();
    expect(d.store.active!.type.length, 40);
    fake.answerStart(StartRequest(
      requestId: fake.lastStartId,
      status: 'ready',
      proposal: const StartProposal(kind: 'gym', type: 'Late'),
    ));
    await t.pumpAndSettle();
    expect(d.store.active!.type, isNot('Late'));
  });

  testWidgets('Something new offline: no request, an empty session at once', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t, connected: false);
    await openStart(t);
    await typeAndPrepare(t, 'hotel gym, 30 min');
    await t.pumpAndSettle();
    expect(fake.startSent, isEmpty);
    expect(d.store.active!.type, 'Hotel gym');
    expect(d.store.active!.exercises, isEmpty);
    expect(d.outbox.length, 0);
  });

  testWidgets('offline, a proposal starts from the local plan (own last session)', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await openHome(t, connected: false);
    await openStart(t);
    // Local proposals come from the log: Home is the most often.
    await t.tap(find.text('Home · Quick'));
    await t.pumpAndSettle();
    expect(d.store.active!.type, 'Home');
    expect(d.store.active!.exercises.map((Exercise e) => e.name), <String>['Press-up', 'Squat']);
  });

  testWidgets('Start empty, without a plan: an empty Gym session', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await openHome(t);
    await openStart(t);
    await t.tap(find.text('Start empty, without a plan ›'));
    await t.pumpAndSettle();
    expect(d.store.active!.type, 'Gym');
    expect(d.store.active!.exercises, isEmpty);
  });
}
