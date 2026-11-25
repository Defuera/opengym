// Visual proof of the chat composer when offline. Not part of the normal suite.
//   flutter test test/shots/chat_offline_shots.dart
// Writes offline-send.png: a "Not sent" bubble, a "Sending…" bubble, the quiet
// offline line and the composer, on.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/screens/chat_screen.dart';
import 'package:opengym/stores/connection_store.dart';
import 'package:opengym/theme.dart';

import '../support/fake_convex_client.dart';
import '../support/load_fonts.dart';
import '../support/test_deps.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/chat';

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  tearDownAll(() => OG.fontFamily = null);

  testWidgets('Chat offline: sending, not sent, composer on', (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 3, 700 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final GlobalKey key = GlobalKey();
    final FakeConvexClient fake = FakeConvexClient();
    final deps = await testDeps(fake);
    deps.coach.start();
    await deps.coach.startNewChat();
    // First message: the server is unreachable, so it ends as "Not sent".
    fake.online = false;
    await deps.coach.send('Knee felt fine on squats today');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    // Second message: waiting behind it, shown as "Sending…".
    await deps.coach.send('What should I do on Thursday?');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    deps.connection.state = ConnState.offline;
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
        home: ChatScreen(deps: deps),
      ),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() async {
      final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await b.toImage(pixelRatio: 3);
      final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_out).create(recursive: true);
      await File('$_out/offline-send.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await t.pumpWidget(const SizedBox());
    deps.outbox.dispose();
  });
}
