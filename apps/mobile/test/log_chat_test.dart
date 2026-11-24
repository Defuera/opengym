import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/pickers.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/chat_screen.dart';
import 'package:opengym/screens/entry_screen.dart';
import 'package:opengym/screens/home_screen.dart';
import 'package:opengym/screens/session_recap_screen.dart';
import 'package:opengym/stores/connection_store.dart';
import 'package:opengym/widgets/composer_bar.dart';

import 'support/chat_fixtures.dart';
import 'support/fake_convex_client.dart';
import 'support/sheet_fixtures.dart';
import 'support/test_deps.dart';

const Key _send = ValueKey<String>('composer-send');
const Key _camera = ValueKey<String>('composer-camera');

const LogDraft _meal = LogDraft(kind: 'meal', summary: 'Dinner: pasta', at: 1700000000000);

const LogDraft _run = LogDraft(
  kind: 'training',
  summary: 'Easy run',
  at: 1700000000000,
  session: LogDraftSession(
    type: 'Run',
    focus: 'Easy',
    minutes: 45,
    distanceKm: 8,
    exercises: <(String, String)>[('Strides', '4 x 20 s')],
  ),
  goal: 'Run 10 km, 2 a week',
  limit: 'Knee: sore (avoid deep squats)',
  note: 'Felt fine after the first km',
);

Future<(FakeConvexClient, AppDeps)> _home(WidgetTester t, {Pickers? pickers, bool connected = true}) async {
  t.view.physicalSize = const Size(800, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final FakeConvexClient fake = FakeConvexClient();
  final AppDeps d = await testDeps(fake, pickers: pickers, connected: connected, sessions: sheetLog);
  d.coach.start();
  d.entries.start();
  await t.pumpWidget(MaterialApp(home: HomeScreen(deps: d)));
  await t.pump();
  return (fake, d);
}

/// Home, the plus, the Log tab: the log chat opens at once.
Future<void> _openLog(WidgetTester t) async {
  await openStart(t);
  await t.tap(inSheet(find.text('Log')));
  // Closing a thread that was open waits on a stream cancel, which needs real time.
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await t.pumpAndSettle();
}

Future<void> _type(WidgetTester t, String s) async {
  await t.enterText(find.byType(TextField).last, s);
  await t.pump();
  await t.tap(find.byKey(_send));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('the Log tab opens the chat at once in a new thread with screen log, focused, with the hint',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _home(t);
    await _openLog(t);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('New log'), findsOneWidget);
    expect(find.text('Write it, or add a photo or a file. I will work out what it is.'), findsOneWidget);
    expect(find.byKey(_camera), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('composer-plus')), findsOneWidget);
    expect(t.widget<TextField>(find.byType(TextField).last).focusNode!.hasFocus, isTrue);
    expect(find.text('Something new: "padel"'), findsNothing);
    final String first = d.coach.currentId!;
    await _type(t, 'Pasta for dinner');
    expect(fake.sentContexts.single!.screen, 'log');
    expect(fake.serverThreads, hasLength(1));
    // Back out and open Log again: a new thread, not the old one.
    await t.tap(find.byIcon(Icons.chevron_left));
    await t.pumpAndSettle();
    await _openLog(t);
    expect(d.coach.currentId, isNot(first));
    expect(d.coach.isDraft, isTrue);
  });

  testWidgets('a photo alone is sent from the camera button with empty text and the log context',
      (WidgetTester t) async {
    final FakePickers pickers = FakePickers(photo: UploadItem(path: 'p.png', name: 'plate.png', bytes: tinyPng));
    final (FakeConvexClient fake, AppDeps d) = await _home(t, pickers: pickers);
    await _openLog(t);
    await t.tap(find.byKey(_camera));
    await t.pumpAndSettle();
    expect(pickers.calls, <String>['camera']);
    expect(d.coach.attachments, hasLength(1));
    await t.tap(find.byKey(_send));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final Message m = fake.serverMessages.values.single.single;
    expect(m.text, '');
    expect(m.fileIds, hasLength(1));
    expect(m.context!.screen, 'log');
  });

  testWidgets('the draft card shows the kind, summary, time and each optional part; buttons while open',
      (WidgetTester t) async {
    final (FakeConvexClient fake, _) = await _home(t);
    await _openLog(t);
    await _type(t, 'ran 8k');
    final String thread = fake.serverThreads.keys.single;
    fake.logDrafted(thread, 'Here is the log.', _run);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Training'), findsOneWidget);
    expect(find.text('Easy run'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('log-draft-when')), findsOneWidget);
    expect(find.text('Run, Easy · 45 min · 8 km'), findsOneWidget);
    expect(find.text('Strides'), findsOneWidget);
    expect(find.text('4 x 20 s'), findsOneWidget);
    expect(find.text('Run 10 km, 2 a week'), findsOneWidget);
    expect(find.text('Knee: sore (avoid deep squats)'), findsOneWidget);
    expect(find.text('Felt fine after the first km'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Add or change'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('log-draft-logged')), findsNothing);
  });

  testWidgets('a draft with no optional part shows only the kind, summary and time', (WidgetTester t) async {
    final (FakeConvexClient fake, _) = await _home(t);
    await _openLog(t);
    await _type(t, 'dinner');
    fake.logDrafted(fake.serverThreads.keys.single, 'Log created.', _meal);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Meal'), findsOneWidget);
    expect(find.text('Dinner: pasta'), findsOneWidget);
    for (final String l in <String>['Session', 'Goal', 'Limit', 'Note']) {
      expect(find.text(l), findsNothing, reason: l);
    }
  });

  testWidgets('applied: a Logged mark and no buttons; stale: grey, no buttons', (WidgetTester t) async {
    final (FakeConvexClient fake, _) = await _home(t);
    await _openLog(t);
    await _type(t, 'dinner');
    final String thread = fake.serverThreads.keys.single;
    fake.logDrafted(thread, 'Log created.', const LogDraft(kind: 'meal', summary: 'Old draft', at: 1700000000000, state: 'stale'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Replaced'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
    expect(find.text('Add or change'), findsNothing);
    expect(t.widget<Opacity>(find.ancestor(of: find.byKey(const ValueKey<String>('log-draft')), matching: find.byType(Opacity)).first).opacity, lessThan(1));
    fake.logDrafted(thread, 'Again.', const LogDraft(kind: 'meal', summary: 'Done one', at: 1700000000000, state: 'applied', entryId: 'e1'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey<String>('log-draft-logged')), findsOneWidget);
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('Done sends the answer approve, then the end state has Close and Open', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _home(t);
    fake.serverFiles['f'] = const FileMeta(id: 'f', name: 'x.jpg', mime: 'image/jpeg', size: 1, kind: 'image', createdAt: 1);
    await _openLog(t);
    await _type(t, 'dinner');
    final String thread = fake.serverThreads.keys.single;
    fake.logDrafted(thread, 'Log created.', _meal);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final String turn = fake.serverMessages[thread]!.last.turnId!;
    await t.tap(find.text('Done'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(fake.sentAnswers.last!.id, 'approve');
    expect(fake.sentAnswers.last!.turnId, turn);
    expect(fake.sentContexts.last!.screen, 'log');
    fake.serverEntries['e1'] = (text: 'dinner', fileIds: <String>[], at: 1700000000000, createdAt: 1700000000000);
    fake.logDone(thread, 'Logged: dinner, pasta.', 'e1');
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Logged: dinner, pasta.'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('log-end')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('log-draft-logged')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('log-open')));
    await t.pumpAndSettle();
    expect(find.byType(EntryScreen), findsOneWidget);
    await t.tap(find.byIcon(Icons.chevron_left));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('log-close')));
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(d.coach.currentId, isNotNull);
  });

  testWidgets('a send after an applied draft starts a new log thread', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _home(t);
    await _openLog(t);
    await _type(t, 'dinner');
    final String first = fake.serverThreads.keys.single;
    fake.logDrafted(first, 'Log created.', _meal);
    await t.pump();
    fake.logDone(first, 'Logged: dinner.', 'e1');
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(d.coach.logDone, isTrue);
    // Opening a new thread closes the old one: a stream cancel that needs real time.
    await t.enterText(find.byType(TextField).last, 'also a coffee');
    await t.pump();
    await t.tap(find.byKey(_send));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(fake.serverThreads, hasLength(2));
    final String second = fake.serverThreads.keys.firstWhere((String k) => k != first);
    expect(fake.serverMessages[first], hasLength(3)); // user, draft, Logged: untouched
    expect(fake.serverMessages[second]!.single.text, 'also a coffee');
    expect(fake.serverMessages[second]!.single.context!.screen, 'log');
    expect(find.text('Logged: dinner.'), findsNothing);
  });

  testWidgets('offline: the composer says so, and typed text and a picked photo are kept', (WidgetTester t) async {
    final FakePickers pickers = FakePickers(photo: UploadItem(path: 'p.png', name: 'plate.png', bytes: tinyPng));
    final (FakeConvexClient fake, AppDeps d) = await _home(t, pickers: pickers);
    await _openLog(t);
    await t.tap(find.byKey(_camera));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'pasta');
    d.connection.state = ConnState.offline;
    d.connection.notifyListeners();
    await t.pump();
    expect(find.text('Offline. Chat needs a connection to send.'), findsOneWidget);
    expect(find.byType(ComposerBar), findsOneWidget);
    expect(d.coach.attachments, hasLength(1));
    // Back online: nothing was lost, one send carries both.
    d.connection.state = ConnState.connected;
    d.connection.notifyListeners();
    await t.pump();
    expect(find.text('pasta'), findsOneWidget);
    await t.tap(find.byKey(_send));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final Message m = fake.serverMessages.values.single.single;
    expect(m.text, 'pasta');
    expect(m.fileIds, hasLength(1));
  });

  testWidgets('the entry screen lists what the entry made; the recap links back "From your log"',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _home(t);
    final Session s = d.store.sessions.last;
    fake.serverEntries['e1'] = (text: 'ran', fileIds: <String>[], at: 1700000000000, createdAt: 1700000000000);
    fake.serverEntryReads['e1'] = EntryRead(status: 'ready', kind: 'training', summary: 'Run', made: EntryMade(sessionId: s.id, goalId: 'g', limitId: 'l'));
    fake.serverChanged(() {});
    await t.pump();
    await t.pump();
    Navigator.of(t.element(find.byType(HomeScreen))).push(MaterialPageRoute<void>(
        builder: (BuildContext c) => EntryScreen(deps: d, entryId: 'e1')));
    await t.pumpAndSettle();
    expect(find.text('Session added \u203a'), findsOneWidget);
    expect(find.text('Goal added \u203a'), findsOneWidget);
    expect(find.text('Limit added'), findsOneWidget);
    await t.tap(find.text('Session added \u203a'));
    await t.pumpAndSettle();
    expect(find.byType(SessionRecapScreen), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('recap-from-log')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('recap-from-log')));
    await t.pumpAndSettle();
    expect(find.byType(EntryScreen), findsOneWidget);
  });
}
