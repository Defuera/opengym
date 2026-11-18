import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/tracker_source.dart';
import 'package:opengym/screens/tracker_screen.dart';

Future<void> _open(WidgetTester t, FakeTrackerSource source) async {
  await t.pumpWidget(MaterialApp(home: TrackerScreen(source: source, now: () => DateTime(2026, 11, 18, 12))));
  await t.pumpAndSettle();
}

const String _footer = 'Nothing is sent anywhere yet. This screen only shows what the phone has.';

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
}
