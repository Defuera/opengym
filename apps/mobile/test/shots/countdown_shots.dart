// Visual proof of the countdown on the session screen. Not part of the normal
// suite (no _test suffix). Run by path:
//   flutter test test/shots/countdown_shots.dart
// It writes idle.png (card with Start), running.png (countdown running) and
// seconds.png (a 30 s hold, idle card) at
// 390x844 logical px, pixel ratio 3.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/store.dart';
import 'package:opengym/stores/countdown_store.dart';
import 'package:opengym/theme.dart';

import '../support/load_fonts.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/countdown';

Future<void> _save(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image img = await b.toImage(pixelRatio: 3);
    final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_out).create(recursive: true);
    await File('$_out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  tearDownAll(() => OG.fontFamily = null);

  testWidgets('session screen with the countdown', (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    DateTime now = DateTime(2026, 11, 19, 10);
    final AppStore store = AppStore(
      InMemorySessionRepository(),
      countdown: CountdownStore(now: () => now, alert: () {}),
    );
    await store.load();
    store.begin(activity: 'Gym', focus: 'Cardio', prepared: <Exercise>[
      Exercise(
        id: 'b',
        name: 'Stationary bike',
        measure: measureTime,
        fresh: false,
        sets: <SetEntry>[SetEntry.time(10), SetEntry.time(10)],
      ),
      Exercise(id: 'w', name: 'Wall sit', measure: measureTime, fresh: false, sets: <SetEntry>[SetEntry.time(0.5)]),
    ]);
    final GlobalKey key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
        home: SessionScreen(store: store),
      ),
    ));
    await t.pump();
    await _save(t, key, 'idle');
    await t.tap(find.byKey(const ValueKey<String>('countdown-start')));
    await t.pump();
    now = now.add(const Duration(minutes: 3, seconds: 12));
    await t.pump(const Duration(milliseconds: 250));
    await _save(t, key, 'running');
    store.countdown.cancel();
    store.pickExercise(1);
    await t.pump();
    await _save(t, key, 'seconds');
    await t.pumpWidget(const SizedBox.shrink());
  });
}
