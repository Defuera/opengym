// Visual proof of the note path. Not part of the normal suite. Run by path:
//   flutter test test/shots/note_ui_shots.dart
// It writes 1-log-tab.png and 2-note-form.png to the shots folder.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/screens/home_screen.dart';
import 'package:opengym/theme.dart';

import '../support/fake_convex_client.dart';
import '../support/load_fonts.dart';
import '../support/sheet_fixtures.dart';
import '../support/test_deps.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/note';

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

  testWidgets('the Log tab and the note form', (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final GlobalKey key = GlobalKey();
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake, sessions: sheetLog);
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
        home: HomeScreen(deps: d),
      ),
    ));
    await t.pump();
    await openLog(t);
    await _save(t, key, '1-log-tab');
    await t.tap(find.byKey(const ValueKey<String>('note-text')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Dinner');
    await t.pump();
    await _save(t, key, '2-note-form');
  });
}
