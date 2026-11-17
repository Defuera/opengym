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
  fake.predictions.set(const Stored<List<Prediction>>(<Prediction>[
    Prediction(kind: 'gym', type: 'Gym', focus: 'Upper', reason: 'Last upper session was 13 Nov'),
    Prediction(kind: 'gym', type: 'Home', focus: 'Quick', reason: 'Done 3 times'),
  ], stored: true, source: 'ai'));
  fake.plans[FakeConvexClient.planKey(activity: 'Gym', focus: 'Upper')] =
      Live<Stored<Plan>>(const Stored<Plan>(sheetPlan, stored: true, source: 'ai'));
  final AppDeps d = await testDeps(fake, connected: connected, sessions: sessions ?? sheetLog);
  d.plans.start();
  await t.pumpWidget(MaterialApp(home: HomeScreen(deps: d)));
  await t.pump();
  return (fake, d);
}

Future<void> openStart(WidgetTester t) async {
  await t.tap(find.text('Start session'));
  await t.pumpAndSettle();
}

Future<void> typeAndPrepare(WidgetTester t, String text) async {
  await t.enterText(find.byType(TextField), text);
  await t.tap(find.text('Prepare'));
  await t.pump();
}

Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

