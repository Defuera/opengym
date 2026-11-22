import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_client.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/theme.dart';

import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

const ValueKey<String> _icon = ValueKey<String>('why-icon');
const ValueKey<String> _figure = ValueKey<String>('why-figure');

Future<(FakeConvexClient, AppDeps)> _open(WidgetTester t, {bool connected = true}) async {
  t.view.physicalSize = const Size(390 * 2, 844 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final FakeConvexClient fake = FakeConvexClient();
  final AppDeps d = await testDeps(fake, connected: connected);
  d.store.begin(
    focus: 'Shoulders',
    rationale: 'Shoulders are due.',
    prepared: <Exercise>[
      Exercise(id: 'l', name: 'Lateral Raise', fresh: false, sets: <SetEntry>[for (int i = 0; i < 3; i++) SetEntry(reps: 12, kg: 6)]),
      Exercise(id: 'w', name: 'Warm-Up', measure: measureTime, fresh: false, sets: <SetEntry>[SetEntry.time(2), SetEntry.time(3)]),
    ],
  );
  await t.pumpWidget(MaterialApp(
    theme: ThemeData(scaffoldBackgroundColor: OG.ground),
    home: SessionScreen(store: d.store, deps: d),
  ));
  await t.pumpAndSettle();
  return (fake, d);
}

void main() {
  testWidgets('the icon opens the sheet with the figure from the answer', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps _) = await _open(t);
    fake.planLoadAnswer = <String, int>{'delts': 3, 'chest': 0};
    expect(find.text('Why this?'), findsNothing);
    await t.tap(find.byKey(_icon));
    await t.pumpAndSettle();
    expect(find.text('Shoulders are due.'), findsOneWidget);
    expect(find.byKey(_figure), findsOneWidget);
  });

  testWidgets('the request carries sets for a rep exercise and minutes for a time exercise', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps _) = await _open(t);
    fake.planLoadAnswer = <String, int>{'delts': 2};
    await t.tap(find.byKey(_icon));
    await t.pumpAndSettle();
    // The screen asks once for the figure at the title, and again when the sheet opens.
    expect(fake.planLoadRequests.length, 2);
    final List<PlanLoadItem> sent = fake.planLoadRequests.last;
    expect(sent.map((PlanLoadItem x) => x.toJson()), <Map<String, dynamic>>[
      <String, dynamic>{'name': 'Lateral Raise', 'sets': 3, 'minutes': 0},
      <String, dynamic>{'name': 'Warm-Up', 'sets': 0, 'minutes': 5},
    ]);
  });

  testWidgets('offline: the sheet shows the text, no figure, no request', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps _) = await _open(t, connected: false);
    fake.planLoadAnswer = <String, int>{'delts': 3};
    await t.tap(find.byKey(_icon));
    await t.pumpAndSettle();
    expect(find.text('Shoulders are due.'), findsOneWidget);
    expect(find.byKey(_figure), findsNothing);
    expect(fake.planLoadRequests, isEmpty);
  });

  testWidgets('a failed request and an all-zero answer show no figure', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps _) = await _open(t);
    fake.planLoadFails = true;
    await t.tap(find.byKey(_icon));
    await t.pumpAndSettle();
    expect(find.text('Shoulders are due.'), findsOneWidget);
    expect(find.byKey(_figure), findsNothing);
    await t.tap(find.byKey(const ValueKey<String>('og-sheet-close')));
    await t.pumpAndSettle();
    fake.planLoadFails = false;
    fake.planLoadAnswer = <String, int>{'delts': 0, 'chest': 0};
    await t.tap(find.byKey(_icon));
    await t.pumpAndSettle();
    expect(find.byKey(_figure), findsNothing);
  });
}
