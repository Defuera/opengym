// Visual proof of the exercise comment (ADR-043). Not part of the normal suite
// (the file name has no _test suffix). Run by path:
//   flutter test test/shots/comment_shots.dart
// It writes 1-comment-sheet.png (the sheet with text and one photo) and
// 2-exercise-card.png (the exercise card with a comment and thumbnails) to the
// shots folder, at 390 px width, pixel ratio 3.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/upload_item.dart';
import 'package:opengym/screens/comment_sheet.dart';
import 'package:opengym/screens/session_parts.dart';
import 'package:opengym/theme.dart';

import '../support/chat_fixtures.dart';
import '../support/fake_convex_client.dart';
import '../support/load_fonts.dart';
import '../support/plans.dart';
import '../support/test_deps.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/comment';

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

/// A plain picture to stand for a photo: a sky, a floor and a bike-like shape.
Future<Uint8List> _photo(Color sky, Color floor) async {
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final Canvas c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, 240, 240), Paint()..color = sky);
  c.drawRect(const Rect.fromLTWH(0, 160, 240, 80), Paint()..color = floor);
  final Paint line = Paint()
    ..color = const Color(0xFF111111)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 8;
  c.drawCircle(const Offset(70, 170), 34, line);
  c.drawCircle(const Offset(170, 170), 34, line);
  c.drawLine(const Offset(70, 170), const Offset(120, 100), line);
  c.drawLine(const Offset(120, 100), const Offset(170, 170), line);
  c.drawLine(const Offset(120, 100), const Offset(150, 100), line);
  final ui.Image img = await rec.endRecording().toImage(240, 240);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

class _Host extends StatelessWidget {
  const _Host({required this.deps});

  final AppDeps deps;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey<String>('open'),
            onPressed: () => showCommentSheet(context, deps, text: null, fileIds: const <String>[]),
            child: const Text('open'),
          ),
        ),
      );
}

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  tearDownAll(() => OG.fontFamily = null);

  testWidgets('1: the comment sheet with text and one photo', (WidgetTester t) async {
    final GlobalKey key = _view(t, 760);
    final Uint8List p = (await t.runAsync(() => _photo(const Color(0xFFBFE3F5), const Color(0xFFD9C7A3))))!;
    final AppDeps d = await testDeps(FakeConvexClient(),
        pickers: FakePickers(photo: UploadItem(path: 'bike.png', name: 'bike.png', bytes: p)), voice: FakeVoiceRecorder());
    await t.pumpWidget(_app(key, _Host(deps: d)));
    await t.tap(find.byKey(const ValueKey<String>('open')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('composer-camera')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Level 9, heart rate 140. Right shoulder felt tight on the last set.');
    await t.pumpAndSettle();
    await t.runAsync(() async {
      for (final Element e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await t.pump();
    await _save(t, key, '1-comment-sheet');
  });

  testWidgets('2: the exercise card with a comment and thumbnails', (WidgetTester t) async {
    final GlobalKey key = _view(t, 620);
    final Uint8List a = (await t.runAsync(() => _photo(const Color(0xFFBFE3F5), const Color(0xFFD9C7A3))))!;
    final Uint8List b = (await t.runAsync(() => _photo(const Color(0xFFF5D9BF), const Color(0xFFA3C7D9))))!;
    final AppDeps d = await testDeps(FakeConvexClient());
    d.coach.rememberFile('p1', UploadItem(path: 'a.png', name: 'a.png', bytes: a));
    d.coach.rememberFile('p2', UploadItem(path: 'b.png', name: 'b.png', bytes: b));
    d.store.begin(focus: 'Push', prepared: pushPlan());
    d.store.setComment('Level 9, heart rate 140. Right shoulder felt tight on the last set.', <String>['p1', 'p2']);
    await t.pumpWidget(_app(
      key,
      Scaffold(
        body: SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: SessionPanel(store: d.store, deps: d))),
      ),
    ));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      for (final Element e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await t.pump();
    await _save(t, key, '2-exercise-card');
  });
}
