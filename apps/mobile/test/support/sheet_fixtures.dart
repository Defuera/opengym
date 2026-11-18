import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/home_screen.dart';

import 'fake_convex_client.dart';
import 'test_deps.dart';

const int sheetNow = 1700000000000;

Session setsSession(String type, String focus, int ago, List<String> names) => Session(
      id: '$type$focus$ago',
      kind: 'gym',
      type: type,
      focus: focus,
      startedAt: sheetNow - ago * 86400000,
      endedAt: sheetNow - ago * 86400000,
      exercises: <Exercise>[
        for (final String n in names)
          Exercise(id: n, name: n, sets: <SetEntry>[SetEntry(reps: 10, kg: 20, done: true)]),
      ],
    );

Session actSession(String type, int ago, {int? minutes, double? km}) => Session(
      id: '$type$ago',
      kind: 'activity',
      type: type,
      startedAt: sheetNow - ago * 86400000,
      endedAt: sheetNow - ago * 86400000,
      minutes: minutes,
      distanceKm: km,
    );

final List<Session> sheetLog = <Session>[
  setsSession('Gym', 'Upper', 9, <String>['Row']),
  setsSession('Home', 'Quick', 5, <String>['Press-up']),
  setsSession('Home', 'Quick', 3, <String>['Press-up', 'Squat']),
  actSession('Run', 20, km: 13),
  actSession('Cycling', 8, minutes: 25),
  actSession('Cycling', 40, minutes: 30),
  actSession('Bouldering', 90),
];

const Plan sheetPlan = Plan(
  id: 'p',
  focus: 'Upper',
  createdAt: 1,
  source: 'ai',
  rationale: 'Stored plan',
  exercises: <PlanExercise>[
    PlanExercise(name: 'Stored row', sets: <PlanSet>[PlanSet(reps: 8, kg: 40)]),
  ],
);

Future<(FakeConvexClient, AppDeps)> openHome(
  WidgetTester t, {
  bool connected = true,
  List<Session>? sessions,
}) async {
  final FakeConvexClient fake = FakeConvexClient();
  fake.plans[FakeConvexClient.planKey(activity: 'Gym', focus: 'Upper')] =
      Live<Stored<Plan>>(const Stored<Plan>(sheetPlan, stored: true, source: 'ai'));
  final AppDeps d = await testDeps(fake, connected: connected, sessions: sessions ?? sheetLog);
  await t.pumpWidget(MaterialApp(home: HomeScreen(deps: d)));
  await t.pump();
  return (fake, d);
}

/// The Home plus opens the sheet on its Start tab.
Future<void> openStart(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.add));
  await t.pumpAndSettle();
}

/// The Home plus, then the Log tab.
Future<void> openLog(WidgetTester t) async {
  await openStart(t);
  await t.tap(inSheet(find.text('Log')));
  await t.pumpAndSettle();
}

/// Step 1 of the Start tab: taps the row of [type].
Future<void> pickType(WidgetTester t, String type) async {
  await t.tap(inSheet(find.text(type)));
  await t.pumpAndSettle();
}

/// Step 1: scrolls to the "Something else" row and taps it.
Future<void> openOther(WidgetTester t) async {
  await t.scrollUntilVisible(find.text('Something else'), 80, scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
  await t.tap(find.text('Something else'));
  await t.pumpAndSettle();
}

/// The note field of step 2.
const String noteHint = 'Short on time, go easy, left hand is sore…';

/// Taps [type] (a type with sets), types the note and taps "Start".
Future<void> pickAndStart(WidgetTester t, String type, {String? note}) async {
  await pickType(t, type);
  if (note != null) {
    await t.enterText(find.widgetWithText(TextField, noteHint), note);
    await t.pump();
  }
  await t.tap(find.text('Start'));
  await t.pump();
}

Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

