// Visual proof of step D (ADR-032): a goal draft card, a limit draft card and
// the About me entry points. Not part of the normal suite (no _test suffix).
// Run by path: flutter test test/shots/stepd_shots.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/in_memory_about_repository.dart';
import 'package:opengym/screens/about_me_screen.dart';
import 'package:opengym/screens/part_chat.dart';
import 'package:opengym/theme.dart';

import '../support/about_fixtures.dart';
import '../support/fake_convex_client.dart';
import '../support/load_fonts.dart';
import '../support/test_deps.dart';
import 'package:opengym/models.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/stepD';
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

  testWidgets('step D: goal draft, limit draft, About me', (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final GlobalKey key = GlobalKey();
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps d = await testDeps(fake);
    d.coach.start();
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    final InMemoryAboutRepository repo = InMemoryAboutRepository(initial: sampleAbout());
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        navigatorKey: nav,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
        home: AboutMeScreen(about: storeOn(repo), notes: await sampleNotes(), deps: d),
      ),
    ));
    t.view.physicalSize = const Size(390 * 3, 1900 * 3); // tall: shows Limits and Preferences
    await t.pumpAndSettle();
    await _save(t, key, '1-about-me-entry-points');
    t.view.physicalSize = const Size(390 * 3, 844 * 3);

    // A goal: the person says it, the coach drafts it.
    openGoalChat(nav.currentState!, d);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pumpAndSettle();
    await _save(t, key, '2-goal-chat-empty');
    await t.enterText(find.byType(TextField).last, 'I want to bench press 70 kg by spring, training 3 times a week');
    await t.pump();
    await t.tap(find.byKey(_send));
    await _settle(t);
    final String goalThread = fake.serverThreads.keys.single;
    fake.logDrafted(
      goalThread,
      'Understood: a strength goal on Bench press. Check it, then press Done.',
      LogDraft(
        kind: 'Goal',
        summary: 'Bench press 70 kg by spring',
        at: DateTime.now().millisecondsSinceEpoch,
        goalRows: const <(String, String)>[('Exercise', 'Bench press'), ('Target', '70 kg'), ('Per week', '3')],
        noEntry: true,
      ),
    );
    await _settle(t);
    await _save(t, key, '3-goal-draft-card');

    // A limit.
    nav.currentState!.pop();
    await t.pumpAndSettle();
    openLimitChat(nav.currentState!, d, part: 'lower_back');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'my lower back is sore, no deadlifts for a month');
    await t.pump();
    await t.tap(find.byKey(_send));
    await _settle(t);
    final String limitThread = fake.serverThreads.keys.firstWhere((String k) => k != goalThread);
    fake.logDrafted(
      limitThread,
      'A limit for the lower back, with one rule. Check it, then press Done.',
      LogDraft(
        kind: 'Limit',
        summary: 'Lower back',
        at: DateTime.now().millisecondsSinceEpoch,
        limitRows: const <(String, String)>[('Body part', 'Lower back'), ('Avoid', 'deadlifts for a month')],
        noEntry: true,
      ),
    );
    await _settle(t);
    await _save(t, key, '4-limit-draft-card');
  });
}
