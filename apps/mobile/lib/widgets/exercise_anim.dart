import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// How long one pose stays, and how long the cross-fade to the next takes.
const Duration exerciseAnimHold = Duration(milliseconds: 900);
const Duration exerciseAnimFade = Duration(milliseconds: 250);

/// How far the end pose must move so that the parts of the drawing that do
/// not move (the body, the equipment) sit on the same place as in the start
/// pose. The image model does not always draw the figure on the same place in
/// both halves. [rgba] holds the whole image ([w] x [h], small), the start pose
/// in the left half. The result is in parts of the width and height of one
/// half. Zero when no shift is clearly better.
Offset poseShift(Uint8List rgba, int w, int h) {
  final int hw = w ~/ 2;
  if (hw < 4 || h < 4 || rgba.length < w * h * 4) {
    return Offset.zero;
  }
  final Uint8List a = Uint8List(hw * h);
  final Uint8List b = Uint8List(hw * h);
  int dark(int x, int y) {
    final int i = (y * w + x) * 4;
    final int d = 255 - ((rgba[i] * 54 + rgba[i + 1] * 183 + rgba[i + 2] * 19) >> 8);
    return d < 60 ? 0 : d;
  }

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < hw; x++) {
      a[y * hw + x] = dark(x, y);
      b[y * hw + x] = dark(x + hw, y);
    }
  }
  int score(int dx, int dy) {
    int sum = 0;
    for (int y = 0; y < h; y++) {
      final int sy = y - dy;
      if (sy < 0 || sy >= h) {
        continue;
      }
      for (int x = 0; x < hw; x++) {
        final int sx = x - dx;
        if (sx < 0 || sx >= hw) {
          continue;
        }
        final int p = a[y * hw + x];
        final int q = b[sy * hw + sx];
        sum += p < q ? p : q;
      }
    }
    return sum;
  }

  final int maxDx = (hw * 0.2).round();
  final int maxDy = (h * 0.05).round();
  final int zero = score(0, 0);
  int best = zero;
  int bx = 0;
  int by = 0;
  for (int dy = -maxDy; dy <= maxDy; dy++) {
    for (int dx = -maxDx; dx <= maxDx; dx++) {
      final int s = score(dx, dy);
      if (s > best) {
        best = s;
        bx = dx;
        by = dy;
      }
    }
  }
  if (best * 100 < zero * 105) {
    return Offset.zero;
  }
  return Offset(bx / hw, by / h);
}

/// [poseShift] of a loaded image, measured on a small copy.
Future<Offset> poseShiftOf(ui.Image image) async {
  const int w = 192;
  const int h = 128;
  final ui.PictureRecorder rec = ui.PictureRecorder();
  Canvas(rec).drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    const Rect.fromLTWH(0, 0, 192, 128),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final ui.Image small = await rec.endRecording().toImage(w, h);
  final ByteData? data = await small.toByteData();
  small.dispose();
  return data == null ? Offset.zero : poseShift(data.buffer.asUint8List(), w, h);
}

/// A small looping animation from one image that holds two poses side by
/// side: start on the left half, end on the right half. It shows the left
/// half, fades to the right half, and back. Each half has a 3:4 aspect.
///
/// Until the image has loaded, or when it fails, it shows nothing. With
/// animations switched off in the system, it shows only the start pose.
/// [size] is the width; without it the widget fills the width it is given.
class ExerciseAnim extends StatefulWidget {
  const ExerciseAnim({super.key, required this.image, this.size, this.square = false});

  /// A square card that shows the middle of each half (the drawing sits there). For a small picture.
  final bool square;

  final ImageProvider image;
  final double? size;

  @override
  State<ExerciseAnim> createState() => _ExerciseAnimState();
}

class _ExerciseAnimState extends State<ExerciseAnim> {
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(_onImage, onError: _onError);
  bool _loaded = false;
  bool _failed = false;
  bool _end = false;
  bool _still = false;
  Timer? _timer;

  /// The shift of the end pose (see [poseShift]), kept per image.
  static final Map<Object, Offset> _shifts = <Object, Offset>{};
  Offset _shift = Offset.zero;

  Future<void> _measure(ui.Image image) async {
    final ImageProvider of = widget.image;
    Offset? s = _shifts[of];
    if (s == null) {
      final ui.Image copy = image.clone();
      try {
        s = await poseShiftOf(copy);
      } catch (_) {
        s = Offset.zero;
      } finally {
        copy.dispose();
      }
      _shifts[of] = s;
    }
    if (mounted && widget.image == of && s != _shift) {
      setState(() => _shift = s!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _watchImage();
    _syncTimer();
  }

  @override
  void didUpdateWidget(ExerciseAnim old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image) {
      _loaded = false;
      _failed = false;
      _end = false;
      _shift = _shifts[widget.image] ?? Offset.zero;
      _watchImage();
      _syncTimer();
    }
  }

  void _watchImage() {
    final ImageStream next = widget.image.resolve(createLocalImageConfiguration(context));
    if (_stream?.key == next.key) {
      return;
    }
    _stream?.removeListener(_listener);
    _stream = next..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool sync) {
    if (!mounted) {
      return;
    }
    setState(() => _loaded = true);
    _syncTimer();
    _measure(info.image);
  }

  void _onError(Object error, StackTrace? stack) {
    if (mounted) {
      setState(() => _failed = true);
    }
  }

  void _syncTimer() {
    final bool run = _loaded && !_failed && !_still;
    if (!run) {
      _timer?.cancel();
      _timer = null;
      if (_end && mounted) {
        setState(() => _end = false);
      }
      return;
    }
    _timer ??= Timer.periodic(exerciseAnimHold + exerciseAnimFade, (Timer _) {
      if (mounted) {
        setState(() => _end = !_end);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _failed) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final double w = widget.size ?? (c.hasBoundedWidth ? c.maxWidth : 72);
      final double h = widget.square ? w : w * 4 / 3;
      final double innerW = w - 2 * OG.borderWidth;
      final double innerH = innerW * 4 / 3;
      return Container(
        key: const ValueKey<String>('exercise-anim-card'),
        width: w,
        height: h,
        decoration: ogBox(color: OG.ground, radius: 12, shadow: false),
        clipBehavior: Clip.antiAlias,
        // The picture is cut to the inner side of the border, so its square
        // corners do not cover the round corners of the border.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12 - OG.borderWidth),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _half(innerW, innerH, Alignment.centerLeft, -_shift / 2),
              AnimatedOpacity(
                opacity: _end ? 1 : 0,
                duration: exerciseAnimFade,
                child: _half(innerW, innerH, Alignment.centerRight, _shift / 2),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// One half of the image: the full image is twice as wide as the card.
  /// [shift] moves it, in parts of the width and height of the half.
  Widget _half(double w, double h, Alignment side, Offset shift) {
    return ClipRect(
      child: OverflowBox(
        alignment: side,
        minWidth: w * 2,
        maxWidth: w * 2,
        minHeight: h,
        maxHeight: h,
        child: Transform.translate(
          offset: Offset(shift.dx * w, shift.dy * h),
          child: Image(image: widget.image, fit: BoxFit.fill, gaplessPlayback: true),
        ),
      ),
    );
  }
}
