// Visual proof of the Program screens. Not part of the normal suite (the file
// name has no _test suffix). Run by path:
//   flutter test test/shots/program_ui_shots.dart
// It writes 2-program.png
// (the active program in week 2, one slot done), 3-start-sheet.png (the start
// sheet with the program row) and 4-about-me.png (the Programs section) to the
// shots folder, at 390 px width, pixel ratio 3.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/in_memory_about_repository.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/about_me_screen.dart';
import 'package:opengym/screens/home_screen.dart';
import 'package:opengym/screens/program_screen.dart';
import 'package:opengym/stores/context_store.dart';
import 'package:opengym/theme.dart';

import '../support/about_fixtures.dart';
import '../support/fake_convex_client.dart';
import '../support/load_fonts.dart';
import '../support/program_fixtures.dart';
import '../support/sheet_fixtures.dart';
import '../support/test_deps.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/program/app';

Future<void> _save(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image img = await b.toImage(pixelRatio: 3);
    final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_out).create(recursive: true);
    await File('$_out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

GlobalKey _view(WidgetTester t, double height) {
  t.view.physicalSize = Size(390 * 3, height * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  return GlobalKey();
}

Widget _app(GlobalKey key, Widget home) => RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
        home: home,
      ),
    );

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  tearDownAll(() => OG.fontFamily = null);

  testWidgets('2: the Program screen in week 2, one slot done', (WidgetTester t) async {
    final GlobalKey key = _view(t, 1500);
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake);
    fake.programs.set(<Program>[kneeProgram()]);
    await t.pumpWidget(_app(key, ProgramScreen(deps: d, programId: 'prog-1')));
    await t.pump();
    await _save(t, key, '2-program');
  });

  testWidgets('3: the start sheet with the program row', (WidgetTester t) async {
    final GlobalKey key = _view(t, 844);
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake, sessions: sheetLog);
    fake.programs.set(<Program>[kneeProgram()]);
    await t.pumpWidget(_app(key, HomeScreen(deps: d)));
    await t.pump();
    await t.tap(find.byIcon(Icons.add));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('program-row-prog-1')), findsOneWidget);
    await _save(t, key, '3-start-sheet');
  });

  testWidgets('4: About me, the Programs section', (WidgetTester t) async {
    final GlobalKey key = _view(t, 844);
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake);
    fake.programs.set(<Program>[kneeProgram(), kneeProgram(id: 'old', status: 'done', state: 'ended')]);
    final ContextStore notes = await sampleNotes();
    await t.pumpWidget(_app(
      key,
      AboutMeScreen(about: storeOn(InMemoryAboutRepository(initial: sampleAbout())), notes: notes, deps: d),
    ));
    await t.pump();
    await t.scrollUntilVisible(find.byKey(const ValueKey<String>('program-new')), 200);
    await t.pump();
    await _save(t, key, '4-about-me');
  });
}
