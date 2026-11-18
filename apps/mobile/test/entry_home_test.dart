import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/dashboard_view.dart';
import 'package:opengym/screens/entry_screen.dart';
import 'package:opengym/screens/home_recent.dart';
import 'package:opengym/screens/home_screen.dart';
import 'package:opengym/widgets/entry_list_item.dart';
import 'package:opengym/widgets/og_button.dart';

import 'support/entry_fixtures.dart';
import 'support/fake_convex_client.dart';
import 'support/test_deps.dart';

const int _day = 86400000;

/// A session that ended [ago] ms before now, and a note at the same distance.
int _t(double days) => DateTime.now().millisecondsSinceEpoch - (days * _day).round();

Session _s(String type, double daysAgo) => Session(
      id: type,
      kind: 'activity',
      type: type,
      startedAt: _t(daysAgo),
      endedAt: _t(daysAgo),
      minutes: 20,
    );

void _serve(FakeConvexClient fake, String id, String text, int at, {List<String> files = const <String>[]}) {
  fake.serverEntries[id] = (text: text, fileIds: files, at: at, createdAt: at);
}

void main() {
  test('mergeRecent orders sessions and notes by time, newest first', () {
    final List<RecentItem> r = mergeRecent(
      <Session>[_s('Run', 5), _s('Swim', 1)],
      <LogEntry>[note('n1', 'Lunch', _t(3)), note('n2', 'Late', _t(0.5))],
    );
    expect(r.map((RecentItem i) => i.entry?.id ?? i.session!.type), <String>['n2', 'Swim', 'n1', 'Run']);
  });

  test('mergeRecent keeps the first five of the merge', () {
    final List<RecentItem> r = mergeRecent(
      <Session>[for (int i = 0; i < 4; i++) _s('S$i', 10.0 + i)],
      <LogEntry>[for (int i = 0; i < 4; i++) note('n$i', 'N$i', _t(1.0 + i))],
    );
    expect(r, hasLength(5));
    expect(r.where((RecentItem i) => i.entry != null), hasLength(4));
  });

  testWidgets('Home lists a note between the sessions, by time, with its attachment sign',
      (WidgetTester t) async {
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake, sessions: <Session>[_s('Run', 6), _s('Swim', 1)]);
    fake.serverFiles['f1'] = const FileMeta(
        id: 'f1', name: 'meal.jpg', mime: 'image/jpeg', size: 1, kind: 'image', createdAt: 1);
    _serve(fake, 'n1', '', _t(3), files: <String>['f1']);
    _serve(fake, 'n2', 'Eggs on toast\nand coffee', _t(4));
    fake.serverChanged(() {});
    await t.pumpWidget(MaterialApp(home: HomeScreen(deps: d)));
    await t.pump();
    await t.pump();
    final double swim = t.getTopLeft(find.text('Swim')).dy;
    final double photo = t.getTopLeft(find.text('Photo')).dy;
    final double eggs = t.getTopLeft(find.text('Eggs on toast')).dy;
    final double run = t.getTopLeft(find.text('Run')).dy;
    expect(swim, lessThan(photo));
    expect(photo, lessThan(eggs));
    expect(eggs, lessThan(run));
    expect(find.text('and coffee'), findsNothing);
    expect(find.byKey(const ValueKey<String>('entry-attachments')), findsOneWidget);
    expect(find.byType(EntryListItem), findsNWidgets(2));
  });

  testWidgets('notes show with an empty session log', (WidgetTester t) async {
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake);
    _serve(fake, 'n1', 'Slept badly', _t(0.1));
    fake.serverChanged(() {});
    await t.pumpWidget(MaterialApp(home: HomeScreen(deps: d)));
    await t.pump();
    await t.pump();
    expect(find.text('Slept badly'), findsOneWidget);
    expect(find.text('Nothing logged yet.'), findsNothing);
  });

  testWidgets('the server dashboard: the app list replaces the server recent module',
      (WidgetTester t) async {
    const Dashboard dash = Dashboard(days: 7, source: 'rules', modules: <DashboardModule>[
      DashboardModule(type: 'note', text: 'Server note'),
      DashboardModule(
          type: 'recent_sessions',
          items: <ModuleItem>[ModuleItem(title: 'Server row', subtitle: 'x', trailing: 'y')]),
    ]);
    final Widget mine = HomeRecent(
        sessions: <Session>[_s('Run', 2)], entries: <LogEntry>[note('n', 'Mine', _t(1))]);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: DashboardView(dashboard: dash, recent: mine))));
    expect(find.text('Server row'), findsNothing);
    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Server note'), findsOneWidget);
    // Without notes the server list stays.
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: DashboardView(dashboard: dash))));
    expect(find.text('Server row'), findsOneWidget);
    // No server recent module: the list is added at the end.
    const Dashboard bare = Dashboard(days: 7, source: 'rules', modules: <DashboardModule>[
      DashboardModule(type: 'note', text: 'Server note'),
    ]);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: DashboardView(dashboard: bare, recent: mine))));
    expect(find.text('Mine'), findsOneWidget);
  });

  group('detail', () {
    Future<(FakeConvexClient, AppDeps)> open(WidgetTester t) async {
      final FakeConvexClient fake = FakeConvexClient();
      final AppDeps d = await testDeps(fake);
      fake.serverFiles['p'] = const FileMeta(
          id: 'p', name: 'meal.jpg', mime: 'image/jpeg', size: 1, kind: 'image', createdAt: 1);
      fake.serverFiles['d'] = const FileMeta(
          id: 'd', name: 'plan.pdf', mime: 'application/pdf', size: 1, kind: 'pdf', createdAt: 1);
      _serve(fake, 'n1', 'Pasta, then a long walk.\nFelt good.', entryNow, files: <String>['p', 'd']);
      fake.serverChanged(() {});
      await t.pumpWidget(MaterialApp(home: HomeScreen(deps: d)));
      await t.pump();
      await t.pump();
      await t.tap(find.text('Pasta, then a long walk.'));
      await t.pumpAndSettle();
      return (fake, d);
    }

    testWidgets('a tap opens the note: full text, photo as an image, file as a chip, time',
        (WidgetTester t) async {
      await open(t);
      expect(find.byType(EntryScreen), findsOneWidget);
      expect(find.text('Pasta, then a long walk.\nFelt good.'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('plan.pdf'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('entry-when')), findsOneWidget);
    });

    testWidgets('Edit opens the form with the note; a file can be removed and saved',
        (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps d) = await open(t);
      await t.tap(find.byKey(const ValueKey<String>('entry-edit')));
      await t.pumpAndSettle();
      expect(find.text('Edit note'), findsOneWidget);
      expect(find.text('Pasta, then a long walk.\nFelt good.'), findsOneWidget);
      expect(find.text('meal.jpg'), findsOneWidget);
      await t.tap(find.descendant(
          of: find.widgetWithText(Container, 'plan.pdf').first, matching: find.byIcon(Icons.close)));
      await t.pump();
      expect(find.text('plan.pdf'), findsNothing);
      await t.enterText(find.byType(TextField), 'Pasta only');
      await t.pump();
      await t.tap(find.widgetWithText(OgButton, 'Save'));
      await t.pumpAndSettle();
      final e = fake.serverEntries['n1']!;
      expect(e.text, 'Pasta only');
      expect(e.fileIds, <String>['p']);
      expect(e.at, entryNow);
      expect(fake.serverFiles.containsKey('d'), isFalse);
      expect(find.byType(EntryScreen), findsOneWidget);
      expect(find.text('Pasta only'), findsOneWidget);
      expect(d.entries.entries.single.files, hasLength(1));
    });

    testWidgets('Delete asks first; Keep changes nothing; Delete removes and returns',
        (WidgetTester t) async {
      final (FakeConvexClient fake, AppDeps _) = await open(t);
      await t.tap(find.byKey(const ValueKey<String>('entry-delete')));
      await t.pumpAndSettle();
      expect(find.text('Delete this note?'), findsOneWidget);
      expect(find.textContaining('erased for good after 72 hours'), findsOneWidget);
      await t.tap(find.text('Keep it'));
      await t.pumpAndSettle();
      expect(fake.serverEntries, hasLength(1));
      await t.tap(find.byKey(const ValueKey<String>('entry-delete')));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete note'));
      await t.pumpAndSettle();
      expect(fake.serverEntries, isEmpty);
      expect(fake.serverFiles, isEmpty);
      expect(find.byType(EntryScreen), findsNothing);
      expect(find.text('Pasta, then a long walk.'), findsNothing);
    });
  });
}
