// Visual proof of the log chat (ADR-032). Not part of the normal suite (the
// file name has no _test suffix). Run by path:
//   flutter test test/shots/logchat_shots.dart
// It writes 1-log-empty, 2-log-meal, 3-log-run and 4-log-done at 390 px
// width, pixel ratio 3.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/upload_item.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/log_chat.dart';
import 'package:opengym/theme.dart';

import '../support/chat_fixtures.dart';
import '../support/fake_convex_client.dart';
import '../support/load_fonts.dart';
import '../support/test_deps.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/logchat';
const Key _send = ValueKey<String>('composer-send');

Future<void> _save(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image img = await b.toImage(pixelRatio: 3);
    final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_out).create(recursive: true);
    await File('$_out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  tearDownAll(() => OG.fontFamily = null);

  testWidgets('the log chat: empty, meal, run, done', (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final GlobalKey key = GlobalKey();
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake, pickers: FakePickers(photo: UploadItem(path: 'p.png', name: 'plate.png', bytes: tinyPng)));
    d.coach.start();
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        navigatorKey: nav,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    ));
    openLogChat(nav.currentState!, d);
    await t.pumpAndSettle();
    await _save(t, key, '1-log-empty');

    await t.tap(find.byKey(const ValueKey<String>('composer-camera')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'dinner');
    await t.pump();
    await t.tap(find.byKey(_send));
    await _settle(t);
    final String thread = fake.serverThreads.keys.single;
    final int now = DateTime.now().millisecondsSinceEpoch;
    fake.logDrafted(thread, 'Log created. Check it, then press Done.', LogDraft(kind: 'meal', summary: 'Dinner: pasta with tomato sauce', at: now));
    await _settle(t);
    await _save(t, key, '2-log-meal');

    // A new log is a new thread.
    nav.currentState!.pop();
    await t.pumpAndSettle();
    openLogChat(nav.currentState!, d);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'ran 8 km easy, 45 min, left knee a bit sore');
    await t.pump();
    await t.tap(find.byKey(_send));
    await _settle(t);
    final String thread2 = fake.serverThreads.keys.firstWhere((String k) => k != thread);
    fake.logDrafted(
      thread2,
      'Log created. Check it, then press Done.',
      LogDraft(
        kind: 'training',
        summary: 'Easy run, 8 km',
        at: now,
        session: const LogDraftSession(
          type: 'Run',
          focus: 'Easy',
          minutes: 45,
          distanceKm: 8,
          exercises: <(String, String)>[('Strides', '4 x 20 s')],
        ),
        limit: 'Knee: sore',
        note: 'Left knee a bit sore',
      ),
    );
    await _settle(t);
    await _save(t, key, '3-log-run');

    fake.serverEntries['e1'] = (text: 'dinner', fileIds: <String>[], at: now, createdAt: now);
    fake.logDone(thread2, 'Logged: easy run, 8 km. Session added.', 'e1');
    await _settle(t);
    await _save(t, key, '4-log-done');
  });
}
