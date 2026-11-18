import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/activity_log.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/home_screen.dart';
import 'package:opengym/screens/import_screen.dart';
import 'package:opengym/screens/other_activity_screen.dart';
import 'package:opengym/widgets/og_button.dart';
import 'support/fake_convex_client.dart';
import 'support/sheet_fixtures.dart';
import 'support/test_deps.dart';

void main() {
  test('logActivities merges names by key, shows the latest spelling, skips set-based sessions', () {
    final List<LogActivity> a = logActivities(<Session>[
      actSession('run', 9, km: 5),
      actSession('Run ', 2, km: 8),
      actSession('Padel', 1, minutes: 60),
      setsSession('Gym', 'Upper', 3, <String>['Row']),
    ]);
    expect(a.map((LogActivity x) => x.name).toList(), <String>['Run', 'Padel']);
    expect(a.first.count, 2);
    expect(a.first.lastLine(), endsWith('· 8 km'));
  });

  testWidgets('with an empty log the sheets show only the text field and the links',
      (WidgetTester t) async {
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake, connected: false);
    await t.pumpWidget(MaterialApp(home: HomeScreen(deps: d)));
    await t.pump();
    await openStart(t);
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Nothing in your log yet.'), findsOneWidget);
    expect(find.textContaining(' · '), findsNothing);
    expect(find.text('Start empty, without a plan ›'), findsOneWidget);
    await t.tap(inSheet(find.text('Log')));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Import a photo or a file ›'), findsOneWidget);
  });

  testWidgets('Log sheet: time and distance activities, most often first, with the last record',
      (WidgetTester t) async {
    t.view.physicalSize = const Size(800, 1600); // the Note row takes room; show the whole list
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await openHome(t);
    await openLog(t);
    final List<String> order = <String>['Cycling', 'Run', 'Bouldering'];
    double last = -1;
    for (final String n in order) {
      final double y = t.getTopLeft(inSheet(find.text(n))).dy;
      expect(y, greaterThan(last));
      last = y;
    }
    expect(inSheet(find.text('Gym')), findsNothing);
    expect(inSheet(find.text('Home')), findsNothing);
    expect(inSheet(find.textContaining('Last: ')), findsNWidgets(3));
    expect(inSheet(find.textContaining('· 13 km')), findsOneWidget);
    expect(inSheet(find.textContaining('· 25 min')), findsOneWidget);
    expect(inSheet(find.text('Last: ${shortDate(sheetNow - 90 * 86400000)}')), findsOneWidget);
  });

  testWidgets('Log: a tap on an item opens the small log form and saves with distance and note',
      (WidgetTester t) async {
    t.view.physicalSize = const Size(800, 1600); // the Note row takes room; show the whole list
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final (FakeConvexClient _, AppDeps d) = await openHome(t);
    await openLog(t);
    await t.tap(inSheet(find.text('Run')));
    await t.pumpAndSettle();
    expect(find.byType(OtherActivityScreen), findsOneWidget);
    expect(find.descendant(of: find.byType(OtherActivityScreen), matching: find.text('Run')), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'For example 5.2'), '5,2');
    await t.enterText(find.widgetWithText(TextField, '').last, 'windy');
    await t.tap(find.text('Log run'));
    await t.pumpAndSettle();
    final Session s = d.store.sessions.last;
    expect(s.type, 'Run');
    expect(s.kind, 'activity');
    expect(s.distanceKm, 5.2);
    expect(s.note, 'windy');
    expect(find.byType(OtherActivityScreen), findsNothing);
  });

  testWidgets('Log: a new name opens the form for that name', (WidgetTester t) async {
    final (FakeConvexClient _, AppDeps d) = await openHome(t);
    await openLog(t);
    await t.enterText(find.byType(TextField), 'padel');
    await t.tap(inSheet(find.widgetWithText(OgButton, 'Log')));
    await t.pumpAndSettle();
    expect(find.byType(OtherActivityScreen), findsOneWidget);
    await t.tap(find.text('Log padel'));
    await t.pumpAndSettle();
    expect(d.store.sessions.last.type, 'padel');
  });

  testWidgets('Log sheet: the import link opens the import screen', (WidgetTester t) async {
    await openHome(t);
    await openLog(t);
    await t.tap(find.text('Import a photo or a file ›'));
    await t.pumpAndSettle();
    expect(find.byType(ImportScreen), findsOneWidget);
  });
}