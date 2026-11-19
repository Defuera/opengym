import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 2 x 1 px PNG: a red left pixel and a blue right pixel.
Future<Uint8List> tinyArtPng(WidgetTester t) async {
  late Uint8List out;
  await t.runAsync(() async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = const Color(0xFFFF0000));
    c.drawRect(const Rect.fromLTWH(1, 0, 1, 1), Paint()..color = const Color(0xFF0000FF));
    final ui.Image img = await rec.endRecording().toImage(2, 1);
    final ByteData? d = await img.toByteData(format: ui.ImageByteFormat.png);
    out = d!.buffer.asUint8List();
  });
  return out;
}

/// Lets a pending image decode finish (decoding runs outside the fake clock).
Future<void> settleImage(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await t.pump();
}
