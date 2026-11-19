import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// How long one pose stays, and how long the cross-fade to the next takes.
const Duration exerciseAnimHold = Duration(milliseconds: 900);
const Duration exerciseAnimFade = Duration(milliseconds: 250);

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
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _half(innerW, innerH, Alignment.centerLeft),
            AnimatedOpacity(
              opacity: _end ? 1 : 0,
              duration: exerciseAnimFade,
              child: _half(innerW, innerH, Alignment.centerRight),
            ),
          ],
        ),
      );
    });
  }

  /// One half of the image: the full image is twice as wide as the card.
  Widget _half(double w, double h, Alignment side) {
    return ClipRect(
      child: OverflowBox(
        alignment: side,
        minWidth: w * 2,
        maxWidth: w * 2,
        minHeight: h,
        maxHeight: h,
        child: Image(image: widget.image, fit: BoxFit.fill, gaplessPlayback: true),
      ),
    );
  }
}
