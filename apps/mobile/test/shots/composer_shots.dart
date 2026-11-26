// Visual proof of the composer with several attachments. Not part of the normal suite. Run by path:
//   flutter test test/shots/composer_shots.dart
// It writes composer-attachments.png (three thumbnails, mic and send) and attach-sheet.png (two rows).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/pickers.dart';
import 'package:opengym/screens/chat_screen.dart';
import 'package:opengym/theme.dart';

import '../support/chat_fixtures.dart';
import '../support/fake_convex_client.dart';
import '../support/load_fonts.dart';
import '../support/test_deps.dart';

const String _out =
    '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/chat';

Future<void> _save(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image img = await b.toImage(pixelRatio: 3);
    final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_out).create(recursive: true);
    await File('$_out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

/// A 120x120 picture with a gradient, made in memory.
Future<UploadItem> _photo(WidgetTester t) async {
  late Uint8List png;
  await t.runAsync(() async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas c = Canvas(rec);
    c.drawRect(
        const Rect.fromLTWH(0, 0, 120, 120),
        Paint()
          ..shader = ui.Gradient.linear(
              Offset.zero, const Offset(120, 120), const <Color>[Color(0xFFE8A04A), Color(0xFF2448E8)]));
    c.drawCircle(const Offset(60, 52), 24, Paint()..color = const Color(0xFFF2F1EC));
    final ui.Image img = await rec.endRecording().toImage(120, 120);
    png = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  });
  return UploadItem(path: 'arm.png', name: 'arm.png', bytes: png);
}

class _Pick implements Pickers {
  _Pick(this.photo);
  final UploadItem photo;
  @override
  Future<List<UploadItem>> pickFiles() async => <UploadItem>[];
  @override
  Future<UploadItem?> pickPhoto({required bool camera}) async => photo;
  @override
  Future<List<UploadItem>> pickPhotos() async => <UploadItem>[photo, photo, photo];
}

Future<(AppDeps, GlobalKey, FakeConvexClient)> _open(WidgetTester t,
    {bool thread = false, bool voiceThread = false}) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final FakeConvexClient fake = FakeConvexClient();
  final UploadItem photo = await _photo(t);
  final AppDeps d = await testDeps(fake, pickers: _Pick(photo), voice: FakeVoiceRecorder());
  d.coach.start();
  if (voiceThread) {
    await fake.createThread(threadId: 'a', title: 'Squat progress');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await d.coach.openThread('a');
    await fake.sendVoice(threadId: 'a', messageId: 'v1', fileId: 'f1');
    fake.voiceDone('v1', 'Did three sets of squats at 100 kilos, the last one felt heavy.');
    fake.coachAnswers('a', 'Good. Keep 100 next week and add a rep to the last set. How was the depth?');
  } else if (thread) {
    await fake.createThread(threadId: 'a', title: 'Left arm pain');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await d.coach.openThread('a');
    await fake.sendMessage(threadId: 'a', messageId: 'm1', text: 'My left arm hurts near the elbow after pull-ups.');
    fake.coachAnswers('a', 'Thanks. Does it hurt during the pull, or after? Is the pain sharp or dull?');
    await fake.sendMessage(threadId: 'a', messageId: 'm2', text: 'Mostly after. Dull, and a bit sharp when I press on it.');
    fake.coachAnswers('a', 'That can be tendon irritation. Rest the arm two days, then add light work. Send a photo if it swells.');
  } else {
    await d.coach.startNewChat();
  }
  final GlobalKey key = GlobalKey();
  await t.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
      home: ChatScreen(deps: d),
    ),
  ));
  await t.pumpAndSettle();
  return (d, key, fake);
}

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  tearDownAll(() => OG.fontFamily = null);

  testWidgets('composer with three photos, mic and send', (WidgetTester t) async {
    final (AppDeps _, GlobalKey key, FakeConvexClient _) = await _open(t);
    await t.tap(find.byKey(const ValueKey<String>('composer-plus')));
    await t.pumpAndSettle();
    await t.tap(find.text('Photo library'));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      for (final Element e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await t.pump();
    await _save(t, key, 'composer-attachments');
  });

  testWidgets('the plus sheet with two rows', (WidgetTester t) async {
    final (AppDeps _, GlobalKey key, FakeConvexClient _) = await _open(t);
    await t.tap(find.byKey(const ValueKey<String>('composer-plus')));
    await t.pumpAndSettle();
    await _save(t, key, 'attach-sheet');
  });
}
