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

  const String wishHint = 'Short on time, go easy, left hand is sore…';
  const String startToday = "Start today's session";

  testWidgets('the Start tab has one Today card, a wish field and the button; no list, no pencil',
      (WidgetTester t) async {
    await openHome(t);
    await openStart(t);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Gym · Upper'), findsOneWidget);
    expect(find.text('Last upper session was 13 Nov'), findsOneWidget);
    expect(find.text('Home · Quick'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget); // only the "New kind" row
    expect(find.text('Anything for today? (optional)'), findsOneWidget);
    expect(find.widgetWithText(TextField, wishHint), findsOneWidget);
    expect(find.text(startToday), findsOneWidget);
    expect(find.text('New kind of session'), findsOneWidget);
    expect(find.text('Start empty, without a plan ›'), findsOneWidget);
  });

  testWidgets('the Today card shows a short line when there is no pick', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps _) = await openHome(t, sessions: <Session>[]);
    fake.predictions.set(const Stored<List<Prediction>>(<Prediction>[], stored: true, source: 'rules'));
    await openStart(t);
    expect(find.text('The coach picks a session for today.'), findsOneWidget);
    expect(find.text('Gym · Upper'), findsNothing);
  });

  testWidgets('the wish is limited to 200 and survives a tab switch', (WidgetTester t) async {
    await openHome(t);
    await openStart(t);
    await t.enterText(find.widgetWithText(TextField, wishHint), 'w' * 300);
    await t.pump();
    expect(t.widget<TextField>(find.widgetWithText(TextField, 'w' * 200)).controller!.text.length, 200);
    await t.enterText(find.widgetWithText(TextField, 'w' * 200), 'go easy');
    await t.tap(inSheet(find.text('Log')));
    await t.pumpAndSettle();
    await t.tap(inSheet(find.text('Start session')));
    await t.pumpAndSettle();
    expect(find.text('go easy'), findsOneWidget);
  });

  testWidgets('the button sends mode today with the wish and the shown pick, then opens the proposal',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    await openStart(t);
    await t.enterText(find.widgetWithText(TextField, wishHint), '  quick session ');
    await t.tap(find.text(startToday));
    await t.pump();
    expect(find.text('Preparing…'), findsOneWidget);
    expect(find.text("The coach shapes today's session. It opens when ready."), findsOneWidget);
    expect(find.text('Start empty now'), findsOneWidget);
    expect(fake.startToday.single, (true, 'Gym', 'Upper'));
    expect(fake.startSent.single.$2, 'quick session');
    expect(fake.startNames.single, isNull);
    fake.answerStart(StartRequest(
      requestId: fake.lastStartId,
      status: 'ready',
      proposal: const StartProposal(
        kind: 'gym',
        type: 'Gym',
        focus: 'Legs',
        plan: Plan(
          id: 'x',
          focus: 'Legs',
          createdAt: 1,
          source: 'ai',
          rationale: 'Legs are due',
          exercises: <PlanExercise>[
            PlanExercise(name: 'Squat', sets: <PlanSet>[PlanSet(reps: 8, kg: 60)]),
          ],
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(d.store.active!.focus, 'Legs');
    expect(d.store.active!.exercises.single.name, 'Squat');
  });

  testWidgets('keyboard-safe: the Start tab button stays above the keyboard', (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    t.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
    addTearDown(t.view.reset);
    await openHome(t);
    await openStart(t);
    expect(t.getRect(find.text(startToday)).bottom, lessThanOrEqualTo(844 - 300));
    expect(t.takeException(), isNull);
  });

  testWidgets('without a wish the request carries no text', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps _) = await openHome(t);
    await openStart(t);
    await t.tap(find.text(startToday));
    await t.pump();
    expect(fake.startToday.single.$1, isTrue);
    expect(fake.startSent.single.$2, isNull);
  });

  testWidgets('today failed: the shown pick opens as its stored plan', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    await openStart(t);
    await t.tap(find.text(startToday));
    await t.pump();
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'failed'));
    await t.pumpAndSettle();
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(d.store.active!.type, 'Gym');
    expect(d.store.active!.focus, 'Upper');
    expect(d.store.active!.exercises.single.name, 'Stored row');
  });

  testWidgets('today, no answer in 20 s: the shown pick opens', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await openHome(t);
    await openStart(t);
    await t.tap(find.text(startToday));
    await t.pump();
    await t.pump(const Duration(seconds: 21));
    await t.pumpAndSettle();
    expect(d.store.active!.type, 'Gym');
    expect(d.store.active!.exercises.single.name, 'Stored row');
  });

  testWidgets('today, no pick and a failed request: an empty session', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t, sessions: <Session>[]);
    fake.predictions.set(const Stored<List<Prediction>>(<Prediction>[], stored: true, source: 'rules'));
    await openStart(t);
    await t.tap(find.text(startToday));
    await t.pump();
    expect(fake.startToday.single, (true, null, null));
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'failed'));
    await t.pumpAndSettle();
    expect(d.store.active!.exercises, isEmpty);
  });

  testWidgets('today offline: no request, the local pick opens from the log', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t, connected: false);
    await openStart(t);
    await t.tap(find.text(startToday));
    await t.pumpAndSettle();
    expect(fake.startSent, isEmpty);
    expect(d.store.active!.type, 'Home');
    expect(d.store.active!.exercises.map((Exercise e) => e.name), <String>['Press-up', 'Squat']);
  });

  testWidgets('Start empty now in today mode opens an empty Gym session; a late answer opens nothing',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    await openStart(t);
    await t.tap(find.text(startToday));
    await t.pump();
    await t.tap(find.text('Start empty now'));
    await t.pumpAndSettle();
    expect(d.store.active!.type, 'Gym');
    expect(d.store.active!.exercises, isEmpty);
    fake.answerStart(StartRequest(
        requestId: fake.lastStartId, status: 'ready', proposal: const StartProposal(kind: 'gym', type: 'Late')));
    await t.pumpAndSettle();
    expect(d.store.active!.type, isNot('Late'));
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
