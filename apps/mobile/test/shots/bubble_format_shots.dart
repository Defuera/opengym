// ignore_for_file: prefer_const_constructors
// Visual proof of the coach bubble with bold and bullets. Run by path:
//   flutter test test/shots/bubble_format_shots.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/theme.dart';
import 'package:opengym/widgets/chat_bubble.dart';

import '../support/load_fonts.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/chat';

void main() {
  setUpAll(() async {
    if (await loadTestFonts()) {
      OG.fontFamily = 'TestRoboto';
    }
  });
  testWidgets('bubble format', (WidgetTester t) async {
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
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: const <Widget>[
                ChatBubble(text: 'I just ask you on the diagnosis of logged issues and limitations', mine: true),
                SizedBox(height: 12),
                ChatBubble(
                  mine: false,
                  text: 'Stored for your body:\n'
                      '- **Left knee:** a cartilage defect and a tear (ski-prep program)\n'
                      '* **Left elbow:** pain after pull-ups (note)\n'
                      '• **Wrists:** no diagnosis stored\n'
                      '\n'
                      'Tell me if you want to save one.',
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
      await File('$_out/bubble-format.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  });
}
