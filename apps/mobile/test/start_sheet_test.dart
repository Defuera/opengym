import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/other_activity_screen.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/widgets/og_button.dart';
import 'support/fake_convex_client.dart';
import 'support/sheet_fixtures.dart';

void main() {
  testWidgets('Home has the plus and no button row; the plus opens the sheet on Start',
      (WidgetTester t) async {
    await openHome(t);
    expect(find.text('Start session'), findsNothing);
    expect(find.text('Log'), findsNothing);
    expect(find.byIcon(Icons.add), findsOneWidget);
    await openStart(t);
    expect(inSheet(find.text('Start session')), findsOneWidget);
    expect(inSheet(find.text('Log')), findsOneWidget);
    expect(find.text('Gym · Upper'), findsOneWidget);
  });

  testWidgets('the switch shows the log items and keeps typed text of the other tab',
      (WidgetTester t) async {
    await openHome(t);
    await openStart(t);
    await openForm(t);
    await t.enterText(find.widgetWithText(TextField, 'Home'), 'hotel gym');
    await t.tap(inSheet(find.text('Log')));
    await t.pumpAndSettle();
    expect(inSheet(find.text('Run')), findsOneWidget);
    expect(find.text('Gym · Upper'), findsNothing);
    await t.enterText(find.widgetWithText(TextField, 'Something new: "padel"'), 'padel');
    await t.tap(inSheet(find.text('Start session')));
    await t.pumpAndSettle();
    expect(find.text('hotel gym'), findsOneWidget); // the form is still open
    await t.tap(inSheet(find.text('Log')));
    await t.pumpAndSettle();
    expect(find.text('padel'), findsOneWidget);
  });

  testWidgets('Start sheet lists stored proposals; a tap opens the stored plan', (WidgetTester t) async {
    final (FakeConvexClient fake0, AppDeps d) = await openHome(t);
    await openStart(t);
    expect(find.text('Gym · Upper'), findsOneWidget);
    expect(find.text('Home · Quick'), findsOneWidget);
    expect(find.text('Last upper session was 13 Nov'), findsOneWidget);
    expect(find.text('New kind of session'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
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
    await typeAndPrepare(t, 'Hotel gym', wish: '30 min');
    expect(find.text('Preparing…'), findsOneWidget);
    expect(find.text('Start empty now'), findsOneWidget);
    expect(fake.startNames.single, 'Hotel gym');
    expect(fake.startSent.single.$2, '30 min');
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
    await typeAndPrepare(t, 'Padel');
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

  testWidgets('Something new, failed: an empty session with the typed name', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    await openStart(t);
    await typeAndPrepare(t, 'Hotel gym', wish: '30 min');
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'failed'));
    await t.pumpAndSettle();
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(d.store.active!.type, 'Hotel gym');
    expect(d.store.active!.exercises, isEmpty);
  });

  testWidgets('Something new, no answer in 20 s: an empty session', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await openHome(t);
    await openStart(t);
    await typeAndPrepare(t, 'Hotel gym', wish: '30 min');
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
    await typeAndPrepare(t, 'Swim');
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
    await typeAndPrepare(t, 'Hotel gym', wish: '30 min');
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

  group('the Start form', () {
    testWidgets('the dashed row opens the form; back returns to the list', (WidgetTester t) async {
      await openHome(t);
      await openStart(t);
      await openForm(t);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('What do you want? (optional)'), findsOneWidget);
      expect(find.text('It appears in your list next time.'), findsOneWidget);
      expect(find.text('The coach builds the session from this, your log and your limits.'), findsOneWidget);
      expect(find.text('Gym · Upper'), findsNothing);
      await t.tap(find.byTooltip('Back'));
      await t.pumpAndSettle();
      expect(find.text('Gym · Upper'), findsOneWidget);
      expect(find.text('New kind of session'), findsOneWidget);
    });

    testWidgets('an empty name disables the button and the link; limits 40 and 200', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps _) = await openHome(t);
      await openStart(t);
      await openForm(t);
      Finder button() => find.ancestor(of: find.text('Prepare session'), matching: find.byType(OgButton));
      expect(t.widget<OgButton>(button()).onPressed, isNull);
      await t.tap(find.text('Prepare session'), warnIfMissed: false);
      await t.tap(find.text('Start empty ›'), warnIfMissed: false);
      await t.pump();
      expect(fake.startSent, isEmpty);
      await t.enterText(find.widgetWithText(TextField, 'Home'), '   ');
      await t.pump();
      expect(t.widget<OgButton>(button()).onPressed, isNull);
      await t.enterText(find.widgetWithText(TextField, 'Home'), 'y' * 60);
      await t.enterText(find.widgetWithText(TextField, '15 minutes, no equipment, easy on the knee'), 'z' * 300);
      await t.pump();
      expect(t.widget<OgButton>(button()).onPressed, isNotNull);
      expect(t.widget<TextField>(find.widgetWithText(TextField, 'y' * 40)).controller!.text.length, 40);
      expect(t.widget<TextField>(find.widgetWithText(TextField, 'z' * 200)).controller!.text.length, 200);
    });

    testWidgets('Prepare with a name only sends the name and no text', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps _) = await openHome(t);
      await openStart(t);
      await typeAndPrepare(t, '  Hotel gym ');
      expect(find.text('Preparing…'), findsOneWidget);
      expect(fake.startNames.single, 'Hotel gym');
      expect(fake.startSent.single.$2, isNull);
    });

    testWidgets('Prepare with a name and a prompt sends both', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps _) = await openHome(t);
      await openStart(t);
      await typeAndPrepare(t, 'Home', wish: '15 minutes, no equipment');
      expect(fake.startNames.single, 'Home');
      expect(fake.startSent.single.$2, '15 minutes, no equipment');
      expect(find.text('Start empty now'), findsOneWidget);
    });

    testWidgets('Start empty opens an empty session with that name, no request', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await openHome(t);
      await openStart(t);
      await openForm(t);
      await t.enterText(find.widgetWithText(TextField, 'Home'), 'Beach');
      await t.pump();
      await t.tap(find.text('Start empty ›'));
      await t.pumpAndSettle();
      expect(fake.startSent, isEmpty);
      expect(d.store.active!.type, 'Beach');
      expect(d.store.active!.exercises, isEmpty);
    });

    testWidgets('the pencil on a proposal opens the form locked to that activity; the row still opens at once',
        (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps _) = await openHome(t);
      await openStart(t);
      await openForm(t);
      await t.enterText(find.widgetWithText(TextField, '15 minutes, no equipment, easy on the knee'), 'old wish');
      await t.tap(find.byTooltip('Back'));
      await t.pumpAndSettle();
      expect(find.byTooltip('Ask for a custom session'), findsNWidgets(2));
      await t.tap(find.byTooltip('Ask for a custom session').first);
      await t.pumpAndSettle();
      final TextField name = t.widget<TextField>(find.widgetWithText(TextField, 'Gym'));
      expect(name.readOnly, isTrue);
      expect(find.text('old wish'), findsNothing);
      await t.enterText(find.widgetWithText(TextField, '15 minutes, no equipment, easy on the knee'), 'only 20 minutes, no bench');
      await t.tap(find.text('Prepare session'));
      await t.pump();
      expect(fake.startNames.single, 'Gym');
      expect(fake.startSent.single.$2, 'only 20 minutes, no bench');
    });

    testWidgets('typed values and the open form survive a tab switch', (WidgetTester t) async {
      await openHome(t);
      await openStart(t);
      await openForm(t);
      await t.enterText(find.widgetWithText(TextField, 'Home'), 'Hotel');
      await t.enterText(find.widgetWithText(TextField, '15 minutes, no equipment, easy on the knee'), 'short');
      await t.tap(inSheet(find.text('Log')));
      await t.pumpAndSettle();
      await t.tap(inSheet(find.text('Start session')));
      await t.pumpAndSettle();
      expect(find.text('Hotel'), findsOneWidget);
      expect(find.text('short'), findsOneWidget);
    });

    testWidgets('keyboard-safe: the fields scroll and the button stays in view', (WidgetTester t) async {
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      t.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(t.view.reset);
      await openHome(t);
      await openStart(t);
      await openForm(t);
      final Rect r = t.getRect(find.text('Prepare session'));
      expect(r.bottom, lessThanOrEqualTo(844 - 300));
      expect(t.takeException(), isNull);
    });

    testWidgets('the Log tab keeps its single Something new field', (WidgetTester t) async {
      await openHome(t);
      await openLog(t);
      expect(find.text('Something new: "padel"'), findsOneWidget);
      expect(find.text('New kind of session'), findsNothing);
      expect(find.byTooltip('Ask for a custom session'), findsNothing);
    });
  });
}
