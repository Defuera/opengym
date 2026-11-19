import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/widgets/exercise_anim.dart';

/// A light image of [w] x [h] with dark rectangles (left, top, width, height).
Uint8List _image(int w, int h, List<List<int>> dark) {
  final Uint8List out = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 240);
  for (final List<int> r in dark) {
    for (int y = r[1]; y < r[1] + r[3]; y++) {
      for (int x = r[0]; x < r[0] + r[2]; x++) {
        final int i = (y * w + x) * 4;
        out[i] = out[i + 1] = out[i + 2] = 10;
      }
    }
  }
  return out;
}

void main() {
  test('finds how far the body in the end pose is from the start pose', () {
    // Start pose: body at x 40 with a leg down. End pose: body 12 to the
    // right and 2 down, the leg points forward.
    final Uint8List img = _image(192, 128, <List<int>>[
      <int>[40, 20, 6, 70],
      <int>[40, 90, 6, 30],
      <int>[96 + 52, 22, 6, 70],
      <int>[96 + 58, 86, 26, 6],
    ]);
    final Offset s = poseShift(img, 192, 128);
    expect(s.dx, closeTo(-12 / 96, 0.011));
    expect(s.dy, closeTo(-2 / 128, 0.009));
  });

  test('is zero when the body is on the same place', () {
    final Uint8List img = _image(192, 128, <List<int>>[
      <int>[40, 20, 6, 70],
      <int>[40, 90, 6, 30],
      <int>[96 + 40, 20, 6, 70],
      <int>[96 + 46, 84, 26, 6],
    ]);
    expect(poseShift(img, 192, 128), Offset.zero);
  });

  test('is zero for an empty image and for bad input', () {
    expect(poseShift(_image(192, 128, <List<int>>[]), 192, 128), Offset.zero);
    expect(poseShift(Uint8List(8), 192, 128), Offset.zero);
  });
}
