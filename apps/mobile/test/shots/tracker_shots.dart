// Visual proof of the Trackers screen. Not part of the normal suite (no _test
// suffix). Run by path:
//   flutter test test/shots/tracker_shots.dart
// It writes trackers-screen.png to the shots folder, 390 px wide, ratio 3.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/tracker_prefs.dart';
import 'package:opengym/data/tracker_source.dart';
import 'package:opengym/data/tracker_sync.dart';
import 'package:opengym/data/tracker_writer.dart';
import 'package:opengym/screens/tracker_screen.dart';
import 'package:opengym/theme.dart';

import '../support/fake_convex_client.dart';
import '../support/load_fonts.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/tracker';

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  tearDownAll(() => OG.fontFamily = null);

  testWidgets('Trackers: both switches, last sync, a week of data', (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 3, 1500 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final GlobalKey key = GlobalKey();
    final DateTime now = DateTime(2026, 11, 25, 12, 5);
    final List<TrackerDay> days = <TrackerDay>[
      for (int i = 0; i < 7; i++)
        TrackerDay(
          date: DateTime(2026, 11, 25 - i),
          sleepMinutes: 400 + i * 12,
          restingHeartRate: 51 + i % 3,
          steps: 6000 + i * 900,
          activeEnergyKcal: 380.0 + i * 40,
        ),
    ];
    final FakeTrackerSource source = FakeTrackerSource(
      snapshot: TrackerSnapshot(
        sources: const <String>['Fitbit', 'Gym Days'],
        days: days,
        workouts: <TrackerWorkout>[
          TrackerWorkout(id: 'a', type: 'Running', start: DateTime(2026, 11, 24, 7), end: DateTime(2026, 11, 24, 7, 45), minutes: 45, distanceKm: 6.2, avgHeartRate: 148, source: 'Fitbit'),
          TrackerWorkout(id: 'b', type: 'Cycling', start: DateTime(2026, 11, 22, 17), end: DateTime(2026, 11, 22, 18), minutes: 60, distanceKm: 21, avgHeartRate: 131, source: 'Fitbit'),
        ],
      ),
    );
    final TrackerSettings settings = TrackerSettings(
      InMemoryTrackerPrefs(TrackerPrefsState(readOn: true, writeOn: true, lastSyncAt: now, lastDays: 7, lastWorkouts: 2)),
    );
    await settings.load();
    final TrackerSync sync = TrackerSync(source: source, client: FakeConvexClient(), settings: settings, isConnected: () => true, now: () => now);
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
        home: TrackerScreen(source: source, sync: sync, writer: TrackerWriter(source: source, settings: settings), now: () => now),
      ),
    ));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await b.toImage(pixelRatio: 3);
      final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_out).create(recursive: true);
      await File('$_out/trackers-screen.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  });
}
