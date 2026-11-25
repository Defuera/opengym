// Visual proof of the voice composer (ADR-034): the live wave, the quiet
// "Transcribing…" state, and the transcript in the text field. Run by path:
//   flutter test test/shots/voice_shots.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/theme.dart';
import 'package:opengym/widgets/composer_bar.dart';

import '../support/load_fonts.dart';

const String _out = '/Users/admin/dw/tasks/drive-gym-days-development-858ja0cc/shots/voice';

/// A believable stretch of speech: words (loud, uneven) with short pauses and a quiet tail.
List<double> _speech() {
  final math.Random r = math.Random(7);
  final List<double> out = <double>[];
  for (int i = 0; i < 64; i++) {
    final bool pause = (i % 13) >= 10 || i > 58;
    out.add(pause ? 0.02 + r.nextDouble() * 0.05 : 0.25 + r.nextDouble() * 0.6);
  }
  return out;
}

Future<void> _shot(WidgetTester t, String name, Widget bar) async {
  t.view.physicalSize = const Size(1170, 520);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final GlobalKey key = GlobalKey();
  await t.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: OG.ground, fontFamily: 'TestRoboto'),
      home: Scaffold(
        body: Align(alignment: Alignment.bottomCenter, child: bar),
      ),
    ),
  ));
  await t.pump(const Duration(milliseconds: 50));
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

  testWidgets('recording wave', (WidgetTester t) async {
    await _shot(
      t,
      'recording-wave',
      ComposerBar(
        controller: TextEditingController(),
        onSend: () {},
        onMic: () {},
        recording: true,
        recordSeconds: 14,
        recordLevels: _speech(),
        onCancelRecording: () {},
        onStopRecording: () {},
      ),
    );
  });

  testWidgets('transcribing', (WidgetTester t) async {
    await _shot(
      t,
      'transcribing',
      ComposerBar(
        controller: TextEditingController(),
        onSend: () {},
        onMic: () {},
        transcribing: true,
        onDiscardVoice: () {},
      ),
    );
  });

  testWidgets('transcript in the field', (WidgetTester t) async {
    await _shot(
      t,
      'transcript-in-field',
      ComposerBar(
        controller: TextEditingController(text: 'Today I did three sets of squats at 100 kilos, and my left knee felt a bit tight on the last one.'),
        onSend: () {},
        onMic: () {},
        onAttach: () {},
        onCamera: () {},
      ),
    );
  });
}
