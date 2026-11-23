// Visual proof of the Home screen. Not part of the normal suite (no _test
// suffix). Run by path:
//   flutter test test/shots/home_shots.dart
// It writes 1-home-top.png and 2-home-scrolled.png to the shots folder, at
// 390 px width, pixel ratio 3.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/app/deps.dart';
import 'package:opengym/data/convex_types.dart';
import 'package:opengym/models.dart';
import 'package:opengym/screens/home_screen.dart';
import 'package:opengym/theme.dart';

import '../support/fake_convex_client.dart';
import '../support/home_fixtures.dart';
import '../support/load_fonts.dart';
import '../support/test_deps.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/home';

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

  testWidgets('Home: top, and scrolled', (WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final GlobalKey key = GlobalKey();
    final FakeConvexClient fake = FakeConvexClient();
    fake.serverGoals['g-ski'] = skiGoal;
    fake.serverGoals['g-week'] = weeklyGoal;
    final AppDeps d = await testDeps(fake, sessions: homeSessions());
    d.goals.goals = <Goal>[skiGoal, weeklyGoal];
    d.dashboard.select(7);
    fake.dashboards[7]!.set(const Stored<Dashboard>(homeDashboard, stored: true));
    fake.reviews['s5'] = Live<Stored<Review?>>(const Stored<Review?>(homeReview, stored: true));
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
        home: HomeScreen(deps: d, nowMs: homeNow),
      ),
    ));
    await t.pump();
    await t.pump();
    await _save(t, key, '1-home-top');
    await t.drag(find.byType(ListView).first, const Offset(0, -700));
    await t.pump();
    await _save(t, key, '2-home-scrolled');
  });
}
