import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/activity_log.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/log_text_screen.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/widgets/og_button.dart';
import 'support/fake_convex_client.dart';
import 'support/sheet_fixtures.dart';

const StartProposal _legs = StartProposal(
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
);

void main() {
  // The fixture log: Home 2, Cycling 2 (Home is newer), Gym, Run, Bouldering.
  const List<String> order = <String>['Home', 'Cycling', 'Gym', 'Run', 'Bouldering'];

  test('startTypes lists both kinds, merged by key, most used first', () {
    final List<StartType> t = startTypes(<Session>[
      ...sheetLog,
      actSession('cycling ', 1, minutes: 10),
    ]);
    expect(t.map((StartType x) => x.name).toList(), <String>['cycling', 'Home', 'Gym', 'Run', 'Bouldering']); // the latest spelling
    expect(t.map((StartType x) => x.hasSets).toList(), <bool>[false, true, true, false, false]);
    expect(startTypes(<Session>[]), isEmpty);
  });

  testWidgets('step 1 lists the types of the log in order, the first highlighted, then Other',
      (WidgetTester t) async {
    t.view.physicalSize = const Size(800, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await openHome(t);
    await openStart(t);
    expect(inSheet(find.text('Start session')), findsOneWidget);
    double? last;
    for (final String n in order) {
      expect(inSheet(find.text(n)), findsOneWidget, reason: n);
      final double y = t.getTopLeft(inSheet(find.text(n))).dy;
      if (last != null) {
        expect(y, greaterThan(last), reason: n);
      }
      last = y;
    }
    expect(t.getTopLeft(find.text('Other')).dy, greaterThan(last!));
    OgVariant variant(String n) =>
        t.widget<OgButton>(find.ancestor(of: inSheet(find.text(n)), matching: find.byType(OgButton))).variant;
    expect(variant('Home'), OgVariant.accent);
    expect(variant('Gym'), OgVariant.plain);
    // no coach pick, no focus, no reason, no Today card, no "New kind" row
    expect(find.text('Today'), findsNothing);
    expect(find.textContaining(' · '), findsNothing);
    expect(find.text('New kind of session'), findsNothing);
    expect(find.text('Start empty, without a plan ›'), findsOneWidget);
  });

  testWidgets('an empty log shows only Other, a short line and the empty link', (WidgetTester t) async {
    await openHome(t, sessions: <Session>[]);
    await openStart(t);
    expect(find.text('Nothing in your log yet.'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Start empty, without a plan ›'), findsOneWidget);
  });

  testWidgets('a type with sets opens step 2; the back arrow returns to step 1', (WidgetTester t) async {
    await openHome(t);
    await openStart(t);
    await pickType(t, 'Gym');
    expect(find.text('Gym'), findsOneWidget); // the title
    expect(find.text('Anything for today? (optional)'), findsOneWidget);
    expect(find.widgetWithText(TextField, noteHint), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(inSheet(find.text('Home')), findsNothing);
    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();
    expect(inSheet(find.text('Home')), findsOneWidget);
    expect(find.text('Anything for today? (optional)'), findsNothing);
  });

  testWidgets('the note is limited to 2000 and survives a switch to the Log tab', (WidgetTester t) async {
    await openHome(t);
    await openStart(t);
    await pickType(t, 'Gym');
    await t.enterText(find.widgetWithText(TextField, noteHint), 'w' * 2300);
    await t.pump();
    expect(t.widget<TextField>(find.widgetWithText(TextField, 'w' * 2000)).controller!.text.length, 2000);
    await t.enterText(find.widgetWithText(TextField, 'w' * 2000), 'go easy');
    await t.tap(inSheet(find.text('Log')));
    await t.pumpAndSettle();
    await t.tap(inSheet(find.text('Start session')));
    await t.pumpAndSettle();
    expect(find.text('go easy'), findsOneWidget); // still on step 2, note kept
  });

  testWidgets('Start sends the fixed name and the note, shows Preparing, opens the proposal',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    await openStart(t);
    await pickAndStart(t, 'Gym', note: '  left hand is sore ');
    expect(find.text('Preparing…'), findsOneWidget);
    expect(find.text('Start empty now'), findsOneWidget);
    expect(fake.startNames.single, 'Gym');
    expect(fake.startSent.single.$2, 'left hand is sore');
    expect(fake.calls.where((String c) => c.startsWith('saveSession')), isEmpty);
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'ready', proposal: _legs));
    await t.pumpAndSettle();
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(d.store.active!.focus, 'Legs');
    expect(d.store.active!.exercises.single.name, 'Squat');
    expect(d.store.active!.planNote, 'Legs are due');
    expect(find.text('Legs are due'), findsNothing); // the rationale is one tap away
    await t.tap(find.byKey(const ValueKey<String>('why-icon')));
    await t.pumpAndSettle();
    expect(find.text('Legs are due'), findsOneWidget);
  });

  testWidgets('without a note the request carries no text', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps _) = await openHome(t);
    await openStart(t);
    await pickAndStart(t, 'Home');
    expect(fake.startNames.single, 'Home');
    expect(fake.startSent.single.$2, isNull);
  });

  testWidgets('keyboard-safe: the Start button stays above the keyboard', (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    t.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
    addTearDown(t.view.reset);
    await openHome(t);
    await openStart(t);
    await pickType(t, 'Home');
    expect(t.getRect(inSheet(find.text('Start'))).bottom, lessThanOrEqualTo(844 - 300));
    expect(t.takeException(), isNull);
  });

  testWidgets('failed request: the rules plan of that activity opens', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    await openStart(t);
    await pickAndStart(t, 'Home');
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'failed'));
    await t.pumpAndSettle();
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(d.store.active!.type, 'Home');
    expect(d.store.active!.focus, 'Quick');
    expect(d.store.active!.exercises.map((Exercise e) => e.name), <String>['Press-up', 'Squat']);
  });

  testWidgets('no answer in 40 s: the rules plan opens with a notice', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await openHome(t);
    await openStart(t);
    await pickAndStart(t, 'Home');
    await t.pump(const Duration(seconds: 39));
    expect(find.text('Preparing…'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(d.store.active!.type, 'Home');
    expect(d.store.active!.exercises, isNotEmpty);
    expect(find.text('The coach did not answer in time. This is your last Quick session.'), findsOneWidget);
  });

  testWidgets('an answer after 40 s is offered, and a tap takes it', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    await openStart(t);
    await pickAndStart(t, 'Home', note: '2 hours session');
    await t.pump(const Duration(seconds: 41));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('use-coach-plan')), findsNothing);
    fake.answerStart(StartRequest(
        requestId: fake.lastStartId,
        status: 'ready',
        proposal: const StartProposal(
            kind: 'gym',
            type: 'Home',
            focus: 'Legs',
            plan: Plan(id: 'x', focus: 'Legs', createdAt: 1, source: 'ai', rationale: 'Long day', exercises: <PlanExercise>[
              PlanExercise(name: 'Wall Sit', sets: <PlanSet>[PlanSet(reps: 8, kg: 0)]),
            ]))));
    await t.pumpAndSettle();
    expect(d.store.active!.exercises.map((Exercise e) => e.name), <String>['Press-up', 'Squat']); // not swapped by itself
    expect(find.text('The plan of the coach is ready.'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('use-coach-plan')));
    await t.pumpAndSettle();
    expect(d.store.active!.exercises.single.name, 'Wall Sit');
    expect(find.byKey(const ValueKey<String>('use-coach-plan')), findsNothing);
    expect(find.textContaining('did not answer in time'), findsNothing);
  });

  testWidgets('request error: the rules plan opens', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    fake.failNext = const ConvexCallException('nope');
    await openStart(t);
    await pickAndStart(t, 'Gym');
    await t.pumpAndSettle();
    expect(d.store.active!.type, 'Gym');
    expect(d.store.active!.focus, 'Upper');
  });

  testWidgets('offline: no request, the rules plan opens at once', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t, connected: false);
    await openStart(t);
    await pickAndStart(t, 'Home', note: 'quick');
    await t.pumpAndSettle();
    expect(fake.startSent, isEmpty);
    expect(d.store.active!.type, 'Home');
    expect(d.store.active!.exercises.map((Exercise e) => e.name), <String>['Press-up', 'Squat']);
    expect(d.outbox.length, 0);
  });

  testWidgets('a type with sets and no past session starts empty when the request fails', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t, sessions: <Session>[setsSession('Hotel gym', 'Upper', 5, <String>[])]);
    await openStart(t);
    await pickAndStart(t, 'Hotel gym');
    fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'failed'));
    await t.pumpAndSettle();
    expect(d.store.active!.type, 'Hotel gym');
    expect(d.store.active!.exercises, isEmpty);
  });

  testWidgets('Start empty now skips the wait; a late answer opens nothing', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    await openStart(t);
    await pickAndStart(t, 'Gym');
    await t.tap(find.text('Start empty now'));
    await t.pumpAndSettle();
    expect(d.store.active!.type, 'Gym');
    expect(d.store.active!.exercises, isEmpty);
    fake.answerStart(StartRequest(
        requestId: fake.lastStartId, status: 'ready', proposal: const StartProposal(kind: 'gym', type: 'Late')));
    await t.pumpAndSettle();
    expect(d.store.active!.type, isNot('Late'));
  });

  testWidgets('Start empty, without a plan: an empty Gym session', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await openHome(t);
    await openStart(t);
    await t.tap(find.text('Start empty, without a plan ›'));
    await t.pumpAndSettle();
    expect(d.store.active!.type, 'Gym');
    expect(d.store.active!.exercises, isEmpty);
  });

  testWidgets('a time/distance type goes to step 2 with Start, never to the Log form', (WidgetTester t) async {
    t.view.physicalSize = const Size(800, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final (FakeConvexClient fake, AppDeps d) = await openHome(t);
    await openStart(t);
    await pickType(t, 'Run');
    expect(find.byType(LogTextScreen), findsNothing);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('What did you do?'), findsNothing);
    expect(fake.startSent, isEmpty);
    expect(d.store.active, isNull);
  });

  group('Other', () {
    const String hint = 'quick home session, 15 min';
    Finder field() => find.widgetWithText(TextField, hint);
    Finder start() => find.ancestor(of: find.text('Start'), matching: find.byType(OgButton));

    testWidgets('one text field and Start; no name and no shape buttons; Start waits for text',
        (WidgetTester t) async {
      await openHome(t);
      await openStart(t);
      await openOther(t);
      expect(find.text('What do you want to do?'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Sets and reps'), findsNothing);
      expect(find.text('Time or distance'), findsNothing);
      expect(find.text('Name'), findsNothing);
      expect(t.widget<OgButton>(start()).onPressed, isNull);
      await t.enterText(field(), '   ');
      await t.pump();
      expect(t.widget<OgButton>(start()).onPressed, isNull);
      await t.enterText(field(), 'y' * 2300);
      await t.pump();
      expect(t.widget<OgButton>(start()).onPressed, isNotNull);
      expect(t.widget<TextField>(find.widgetWithText(TextField, 'y' * 2000)).controller!.text.length, 2000);
      await t.tap(find.byTooltip('Back'));
      await t.pumpAndSettle();
      expect(inSheet(find.text('Home')), findsOneWidget);
    });

    testWidgets('Start sends the text and no name, shows Preparing, opens the proposal', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await openHome(t);
      await openStart(t);
      await openOther(t);
      await t.enterText(field(), '  i want a quick home session ');
      await t.pump();
      await t.tap(find.text('Start'));
      await t.pump();
      expect(find.text('Preparing…'), findsOneWidget);
      expect(fake.startNames.single, isNull);
      expect(fake.startSent.single.$2, 'i want a quick home session');
      fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'ready', proposal: _legs));
      await t.pumpAndSettle();
      expect(find.byType(SessionScreen), findsOneWidget);
      expect(d.store.active!.exercises.single.name, 'Squat');
      expect(find.byType(LogTextScreen), findsNothing);
    });

    testWidgets('offline: no request, an empty session named from the text before the first comma',
        (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await openHome(t, connected: false);
      await openStart(t);
      await openOther(t);
      await t.enterText(field(), 'hotel gym, 30 min');
      await t.pump();
      await t.tap(find.text('Start'));
      await t.pumpAndSettle();
      expect(fake.startSent, isEmpty);
      expect(d.store.active!.type, 'Hotel gym');
      expect(d.store.active!.exercises, isEmpty);
    });

    testWidgets('a failed request opens an empty session named from the text', (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await openHome(t);
      await openStart(t);
      await openOther(t);
      await t.enterText(field(), 'wing sup, easy');
      await t.pump();
      await t.tap(find.text('Start'));
      await t.pump();
      fake.answerStart(StartRequest(requestId: fake.lastStartId, status: 'failed'));
      await t.pumpAndSettle();
      expect(d.store.active!.type, 'Wing sup');
      expect(d.store.active!.exercises, isEmpty);
    });

    testWidgets('the typed text survives a switch to the Log tab', (WidgetTester t) async {
      await openHome(t);
      await openStart(t);
      await openOther(t);
      await t.enterText(field(), 'hotel gym');
      await t.tap(inSheet(find.text('Log')));
      await t.pumpAndSettle();
      await t.tap(inSheet(find.text('Start session')));
      await t.pumpAndSettle();
      expect(find.text('hotel gym'), findsOneWidget);
    });
  });

  testWidgets('the Log tab keeps its single Something new field', (WidgetTester t) async {
    await openHome(t);
    await openLog(t);
    expect(find.text('Something new: "padel"'), findsOneWidget);
    expect(find.text('New kind of session'), findsNothing);
  });
}
