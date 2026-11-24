import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/outbox.dart';
import 'package:opengym/data/outbox_ops.dart';
import 'package:opengym/data/session_sync.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/activity_log_form.dart';
import 'package:opengym/screens/home_screen.dart';
import 'package:opengym/screens/start_flow.dart';
import 'package:opengym/screens/session_recap_screen.dart';
import 'package:opengym/widgets/og_button.dart';
import 'support/fake_convex_client.dart';
import 'support/sheet_fixtures.dart';

Finder _logButton() => find.ancestor(of: find.text('Log'), matching: find.byType(OgButton));

/// Home -> the form of the time/distance activity Run, as the Start tab opens it
/// when the coach answers with an activity.
Future<(FakeConvexClient, AppDeps)> _openRunForm(WidgetTester t, {bool connected = true}) async {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final (FakeConvexClient, AppDeps) r = await openHome(t, connected: connected);
  // The live session subscription, as compose starts it.
  SessionSync(client: r.$1, store: r.$2.store, outbox: r.$2.outbox).start();
  openLogForm(Navigator.of(t.element(find.byType(HomeScreen))), r.$2, 'Run');
  await t.pumpAndSettle();
  return r;
}

void main() {
  testWidgets('the form is the name and one text field; Log is off while it is empty', (WidgetTester t) async {
    await _openRunForm(t);
    expect(find.byType(ActivityLogForm), findsOneWidget);
    expect(find.descendant(of: find.byType(ActivityLogForm), matching: find.text('Run')), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('What did you do?'), findsOneWidget);
    expect(find.text('45 min, 8 km, easy pace'), findsOneWidget);
    for (final String gone in <String>['Minutes', 'Distance in km (optional)', 'Session type (optional)', 'Note (optional)', 'Clear']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(t.widget<OgButton>(_logButton()).onPressed, isNull);
    await t.enterText(find.byType(TextField), '   ');
    await t.pump();
    expect(t.widget<OgButton>(_logButton()).onPressed, isNull);
    await t.enterText(find.byType(TextField), 'x' * 1200);
    await t.pump();
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text.length, 1000);
    expect(t.widget<OgButton>(_logButton()).onPressed, isNotNull);
  });

  testWidgets('Log sends type and text, opens the recap with a quiet line, and the recap updates live',
      (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openRunForm(t);
    await t.enterText(find.byType(TextField), '45 min, 8 km, easy pace');
    await t.pump();
    await t.tap(find.text('Log'));
    await t.pumpAndSettle();
    final Session s = d.store.sessions.last;
    expect(find.byType(ActivityLogForm), findsNothing);
    expect(find.byType(SessionRecapScreen), findsOneWidget);
    expect(s.type, 'Run');
    expect(s.note, '45 min, 8 km, easy pace');
    expect(fake.loggedTexts[s.id]!.$1, 'Run');
    expect(fake.loggedTexts[s.id]!.$2, '45 min, 8 km, easy pace');
    expect(find.text('Reading your text…'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('recap-activity')), findsNothing);
    expect(find.byKey(const ValueKey<String>('recap-note')), findsOneWidget);
    // The server's job writes the structure; the subscription brings it to the open recap.
    fake.finishParse(s.id, minutes: 45, km: 8);
    await t.pumpAndSettle();
    expect(find.text('Reading your text…'), findsNothing);
    expect(find.text('45 min, 8 km'), findsOneWidget);
    expect(find.text('45 min, 8 km, easy pace'), findsOneWidget); // the note, word for word
  });

  testWidgets('a text the server could not read ends the quiet line and keeps the note', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openRunForm(t);
    await t.enterText(find.byType(TextField), 'felt great');
    await t.pump();
    await t.tap(find.text('Log'));
    await t.pumpAndSettle();
    fake.finishParse(d.store.sessions.last.id, parse: 'failed');
    await t.pumpAndSettle();
    expect(find.text('Reading your text…'), findsNothing);
    expect(find.text('felt great'), findsOneWidget);
  });

  testWidgets('offline: the session is saved and the same write waits in the outbox', (WidgetTester t) async {
    final (FakeConvexClient fake, AppDeps d) = await _openRunForm(t, connected: false);
    await t.enterText(find.byType(TextField), '1h easy');
    await t.pump();
    await t.tap(find.text('Log'));
    await t.pumpAndSettle();
    final Session s = d.store.sessions.last;
    expect(find.byType(SessionRecapScreen), findsOneWidget);
    expect(find.text('Reading your text…'), findsOneWidget);
    expect(fake.loggedTexts, isEmpty);
    expect(d.outbox.ops.single.type, OutboxOp.sessionLogText);
    expect(d.outbox.ops.single.args['text'], '1h easy');
    expect(d.outbox.pendingSessionIds, contains(s.id));
  });

  testWidgets('a log with an activity named Other shows one "Other" row in Start: the free text',
      (WidgetTester t) async {
    t.view.physicalSize = const Size(800, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await openHome(t, sessions: <Session>[...sheetLog, actSession('Other', 2, minutes: 20)]);
    await openStart(t);
    expect(inSheet(find.text('Other')), findsOneWidget);
    await t.tap(inSheet(find.text('Other')));
    await t.pumpAndSettle();
    expect(find.text('What do you want to do?'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });

  group('outbox', () {
    test('a queued text is sent as the logText command; a remove before sending drops it', () async {
      final FakeConvexClient fake = FakeConvexClient();
      bool online = false;
      final Outbox box = Outbox(
        repo: InMemoryOutboxRepository(),
        client: fake,
        isConnected: () => online,
        retryAfter: const Duration(hours: 1),
      );
      final Session a = Session(id: 'a', kind: 'activity', type: 'Run', startedAt: 5, endedAt: 5, note: '30 min', parse: 'pending');
      final Session b = Session(id: 'b', kind: 'activity', type: 'Swim', startedAt: 6, endedAt: 6, note: '1 km', parse: 'pending');
      await box.logText(a);
      await box.logText(b);
      await box.removeSession('b');
      expect(box.ops.map((OutboxOp o) => '${o.type}:${o.targetId}'), <String>['session.logText:a', 'session.remove:b']);
      online = true;
      await box.flush();
      expect(box.isEmpty, isTrue);
      expect(fake.loggedTexts['a'], ('Run', '30 min', 5));
      box.dispose();
    });
  });
}
