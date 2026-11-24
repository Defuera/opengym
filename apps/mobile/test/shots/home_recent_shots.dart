// Visual proof of the compact note row in Home Recent. Not part of the normal
// suite. Run by path: flutter test test/shots/home_recent_shots.dart
// Writes compact-entry.png to the shots folder (390 px wide, ratio 3).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/home_recent.dart';
import 'package:opengym/theme.dart';

import '../support/entry_fixtures.dart';
import '../support/home_fixtures.dart';
import '../support/load_fonts.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/home';

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  tearDownAll(() => OG.fontFamily = null);

  testWidgets('Home Recent: a meal row above two sessions', (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 3, 420 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final GlobalKey key = GlobalKey();
    final LogEntry meal = LogEntry(
      id: 'm',
      text: 'Breakfast granola with yogurt and berries',
      at: homeNow - 3600000,
      createdAt: homeNow - 3600000,
      files: <EntryFile>[imageFile('f1')],
      read: const EntryRead(status: 'ready', kind: 'meal', summary: 'Granola with yogurt and berries in a bowl.'),
    );
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: HomeRecent(
              sessions: <Session>[
                homeGym('s4', 2, 'Legs', <String, double>{'Leg Press': 30, 'Hip Adduction': 35}),
                homeGym('s5', 1, 'Upper', <String, double>{'Row': 42, 'Bench Press': 47.5}),
              ],
              entries: <LogEntry>[meal],
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    await t.runAsync(() async {
      final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await b.toImage(pixelRatio: 3);
      final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_out).create(recursive: true);
      await File('$_out/compact-entry.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  });
}
