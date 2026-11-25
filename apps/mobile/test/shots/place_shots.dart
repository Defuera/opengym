// ignore_for_file: prefer_const_constructors
// Visual proof: the place in the chat header chip and the "Place: Home -> Gym" action line. Run by path:
//   flutter test test/shots/place_shots.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/theme.dart';
import 'package:opengym/widgets/chat_bubble.dart';
import 'package:opengym/widgets/coach_turn_parts.dart';

import '../support/load_fonts.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/place';

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  testWidgets('chat place', (WidgetTester t) async {
    t.view.physicalSize = const Size(1170, 900);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final GlobalKey key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ContextLine(text: 'Gym, Legs · Brisk Walk', place: 'Gym'),
                SizedBox(height: 12),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: ChatBubble(text: "I'm not at home, I'm going to the gym. Give me my usual upper body session.", mine: true),
                ),
                SizedBox(height: 12),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: ChatBubble(mine: false, text: 'Got it, you are at the Gym. Here is your usual upper body session with the bench and the cables.'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: ActionLines(lines: <String>['Place: Home → Gym']),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await b.toImage(pixelRatio: 3);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_out).create(recursive: true);
      await File('$_out/chat-place.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  });
}
