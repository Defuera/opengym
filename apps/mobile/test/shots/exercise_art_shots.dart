// Visual proof of the exercise art on the session screen. Not part of the
// normal suite (no _test suffix). Run by path:
//   flutter test test/shots/exercise_art_shots.dart
// It writes a.png (thumbnail, start pose), b.png (thumbnail, end pose) and
// c.png (the large sheet) at 390x844 logical px, pixel ratio 3.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/session_screen.dart';
import 'package:opengym/stores/exercise_art_store.dart';
import 'package:opengym/theme.dart';
import 'package:opengym/widgets/exercise_anim.dart';

import '../support/art_fixtures.dart';
import '../support/fake_convex_client.dart';
import '../support/load_fonts.dart';
import '../support/test_deps.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/anim/app';

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

  testWidgets('session screen with exercise art', (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final Uint8List png = File('test/assets/legpress_art.png').readAsBytesSync();
    final FakeConvexClient fake = FakeConvexClient();
    final AppDeps base = await testDeps(fake);
    final AppDeps d = AppDeps(
      client: base.client,
      store: base.store,
      connection: base.connection,
      outbox: base.outbox,
      plans: base.plans,
      dashboard: base.dashboard,
      goals: base.goals,
      entries: base.entries,
      context: base.context,
      coach: base.coach,
      imports: base.imports,
      reviews: base.reviews,
      pickers: base.pickers,
      voice: base.voice,
      about: base.about,
      aiModel: base.aiModel,
      tracker: base.tracker,
      places: base.places,
      art: ExerciseArtStore(client: fake, isConnected: () => true, imageFor: (String u) => MemoryImage(png)),
      programs: base.programs,
    );
    d.store.begin(
      activity: 'Gym',
      focus: 'Legs',
      prepared: <Exercise>[
        Exercise(
          id: 'p',
          name: 'Leg Press',
          fresh: false,
          sets: <SetEntry>[for (int i = 0; i < 3; i++) SetEntry(reps: 10, kg: 120)],
        ),
        Exercise(id: 'c', name: 'Leg Curl', fresh: false, sets: <SetEntry>[SetEntry(reps: 12, kg: 40)]),
      ],
    );
    final GlobalKey key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
        home: SessionScreen(store: d.store, deps: d),
      ),
    ));
    await t.pump();
    await t.pump();
    fake.art.set(<String, ExerciseArt>{
      'leg press': const ExerciseArt(name: 'Leg Press', status: 'ready', url: 'x'),
    });
    await t.pump();
    await settleImage(t);
    await _save(t, key, 'a');
    await t.pump(exerciseAnimHold + exerciseAnimFade);
    await t.pump(exerciseAnimFade);
    await _save(t, key, 'b');
    await t.tap(find.byKey(const ValueKey<String>('exercise-anim')));
    await t.pump(const Duration(milliseconds: 400));
    await settleImage(t);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey<String>('exercise-anim-large')), findsOneWidget);
    await _save(t, key, 'c');
    await t.pumpWidget(const SizedBox.shrink());
  });
}
