import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/tracker_prefs.dart';
import 'package:opengym/data/tracker_source.dart';
import 'package:opengym/data/tracker_sync.dart';
import 'package:opengym/data/tracker_writer.dart';
import 'package:opengym/screens/tracker_screen.dart';

import 'support/fake_convex_client.dart';

late FakeConvexClient _client;
late InMemoryTrackerPrefs _prefs;
late TrackerSettings _settings;

Future<void> _open(WidgetTester t, FakeTrackerSource source, {TrackerPrefsState state = const TrackerPrefsState()}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  _client = FakeConvexClient();
  _prefs = InMemoryTrackerPrefs(state);
  _settings = TrackerSettings(_prefs);
  await _settings.load();
  final TrackerSync sync = TrackerSync(
    source: source,
    client: _client,
    settings: _settings,
    isConnected: () => true,
    now: () => DateTime(2026, 11, 18, 12),
  );
  await t.pumpWidget(MaterialApp(
    home: TrackerScreen(
      source: source,
      sync: sync,
      writer: TrackerWriter(source: source, settings: _settings),
      now: () => DateTime(2026, 11, 18, 12),
    ),
  ));
  await t.pumpAndSettle();
}

const String _footer = 'Nothing is sent while the first switch is off. The list below only shows what the phone has.';

void main() {
  testWidgets('not available: says so and offers no buttons', (WidgetTester t) async {
    await _open(t, FakeTrackerSource(isAvailable: false));
    expect(find.text('Not available on this device.'), findsOneWidget);
    expect(find.text('Connect'), findsNothing);
    expect(find.text(_footer), findsOneWidget);
  });

  testWidgets('empty: names the store and the likely cause', (WidgetTester t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await _open(t, FakeTrackerSource());
    expect(find.text('Reads from Apple Health. Your tracker writes there, this app reads it.'), findsOneWidget);
    expect(
      find.text('Nothing found. Check that the app may read from Apple Health, and that your tracker writes to it.'),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('permission not given on Android', (WidgetTester t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _open(t, FakeTrackerSource(error: const TrackerPermissionException()));
    expect(find.textContaining('Reads from Health Connect'), findsOneWidget);
    expect(find.text('Press Connect and allow the app to read.'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a read error shows a retry line', (WidgetTester t) async {
    await _open(t, FakeTrackerSource(error: StateError('x')));
    expect(find.text('Something went wrong. Press Read again.'), findsOneWidget);
  });

  testWidgets('data: sources, workouts and days', (WidgetTester t) async {
    final FakeTrackerSource src = FakeTrackerSource(
      snapshot: TrackerSnapshot(
        sources: const <String>['Fitbit', 'Phone'],
        workouts: <TrackerWorkout>[
          TrackerWorkout(
            id: 'w1',
            type: 'Running',
            start: DateTime(2026, 11, 17, 7),
            end: DateTime(2026, 11, 17, 7, 45),
            minutes: 45,
            distanceKm: 6.2,
            avgHeartRate: 148,
            source: 'Fitbit',
          ),
        ],
        days: <TrackerDay>[
          TrackerDay(date: DateTime(2026, 11, 17), sleepMinutes: 440, restingHeartRate: 52, steps: 8123),
        ],
      ),
    );
    await _open(t, src);
    expect(find.text('Fitbit, Phone'), findsOneWidget);
    expect(find.text('Running · 45 min'), findsOneWidget);
    expect(find.text('Tue 17 Nov · 6.2 km · heart rate 148 · Fitbit'), findsOneWidget);
    expect(find.text('Sleep 7 h 20 min · Resting heart rate 52 · Steps 8123'), findsOneWidget);
    expect(src.readCalls, 1);

    await t.tap(find.byKey(const ValueKey<String>('tracker-read')));
    await t.pumpAndSettle();
    expect(src.readCalls, 2);
    expect(src.connectCalls, 0);

    await t.tap(find.byKey(const ValueKey<String>('tracker-connect')));
    await t.pumpAndSettle();
    expect(src.connectCalls, 1);
    expect(src.readCalls, 3);
  });

  testWidgets('both switches start off and nothing is sent', (WidgetTester t) async {
    final FakeTrackerSource src = FakeTrackerSource();
    await _open(t, src);
    expect(t.widget<Switch>(find.byKey(const ValueKey<String>('tracker-read-switch'))).value, isFalse);
    expect(t.widget<Switch>(find.byKey(const ValueKey<String>('tracker-write-switch'))).value, isFalse);
    expect(find.byKey(const ValueKey<String>('tracker-send')), findsNothing);
    expect(_client.trackerSyncs, isEmpty);
    expect(find.textContaining('Editing or deleting a session later does not change it there.'), findsOneWidget);
  });

  testWidgets('the read switch asks permission, then sends and shows the time and the counts', (WidgetTester t) async {
    final FakeTrackerSource src = FakeTrackerSource(
      snapshot: TrackerSnapshot(
        days: <TrackerDay>[TrackerDay(date: DateTime(2026, 11, 17), steps: 100, activeEnergyKcal: 420)],
        workouts: <TrackerWorkout>[
          TrackerWorkout(id: 'w', type: 'Running', start: DateTime(2026, 11, 17, 7), end: DateTime(2026, 11, 17, 8), minutes: 60, source: 'Fitbit'),
        ],
      ),
    );
    await _open(t, src);
    await t.tap(find.byKey(const ValueKey<String>('tracker-read-switch')));
    await t.pumpAndSettle();
    expect(src.connectCalls, 1);
    expect(_client.trackerSyncs, hasLength(1));
    expect(_prefs.state.readOn, isTrue);
    expect(find.text('Sent Wed 18 Nov, 12:00: 1 day and 1 workout.'), findsOneWidget);
    expect(find.text('Steps 100 · Active 420 kcal'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('tracker-send')));
    await t.pumpAndSettle();
    expect(_client.trackerSyncs, hasLength(2));
  });

  testWidgets('permission refused: the switch stays off and says why', (WidgetTester t) async {
    final FakeTrackerSource src = FakeTrackerSource(connectResult: false);
    await _open(t, src);
    await t.tap(find.byKey(const ValueKey<String>('tracker-read-switch')));
    await t.pumpAndSettle();
    expect(t.widget<Switch>(find.byKey(const ValueKey<String>('tracker-read-switch'))).value, isFalse);
    expect(find.byKey(const ValueKey<String>('tracker-note')), findsOneWidget);
    expect(_client.trackerSyncs, isEmpty);
  });

  testWidgets('the write switch asks for write permission; a refusal shows a line', (WidgetTester t) async {
    final FakeTrackerSource src = FakeTrackerSource(connectWriteResult: false);
    await _open(t, src);
    await t.tap(find.byKey(const ValueKey<String>('tracker-write-switch')));
    await t.pumpAndSettle();
    expect(src.connectWriteCalls, 1);
    expect(t.widget<Switch>(find.byKey(const ValueKey<String>('tracker-write-switch'))).value, isFalse);
    expect(find.byKey(const ValueKey<String>('tracker-write-note')), findsOneWidget);

    src.connectWriteResult = true;
    await t.tap(find.byKey(const ValueKey<String>('tracker-write-switch')));
    await t.pumpAndSettle();
    expect(t.widget<Switch>(find.byKey(const ValueKey<String>('tracker-write-switch'))).value, isTrue);
    expect(_prefs.state.writeOn, isTrue);
    expect(find.byKey(const ValueKey<String>('tracker-write-note')), findsNothing);
  });

  testWidgets('with reading on and nothing sent yet it says so', (WidgetTester t) async {
    await _open(t, FakeTrackerSource(), state: const TrackerPrefsState(readOn: true));
    expect(find.text('Not sent yet.'), findsOneWidget);
  });
}
