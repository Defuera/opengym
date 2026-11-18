import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/voice_recorder.dart';

/// The state of one voice recording in the composer: running or not, the
/// seconds so far, and a short line when the microphone is not allowed.
/// It stops by itself at [maxSeconds] and hands the file to [onRecorded].
class VoiceController extends ChangeNotifier {
  VoiceController({
    required VoiceRecorder recorder,
    required Future<void> Function(UploadItem item) onRecorded,
    this.maxSeconds = 180,
  })  : _recorder = recorder,
        _onRecorded = onRecorded;

  final VoiceRecorder _recorder;
  final Future<void> Function(UploadItem item) _onRecorded;
  final int maxSeconds;

  bool recording = false;
  int seconds = 0;

  /// Short quiet line for the composer, else null.
  String? note;

  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  static const String deniedNote = 'Allow the microphone in Settings to record.';
  static const String failedNote = 'Could not start the recording.';

  Future<void> start() async {
    if (recording || _busy) {
      return;
    }
    _busy = true;
    final VoiceStart r = await _recorder.start();
    _busy = false;
    if (_disposed) {
      await _recorder.cancel();
      return;
    }
    if (r != VoiceStart.started) {
      note = r == VoiceStart.denied ? deniedNote : failedNote;
      notifyListeners();
      return;
    }
    note = null;
    recording = true;
    seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      seconds++;
      if (seconds >= maxSeconds) {
        stopAndSend();
      }
      notifyListeners();
    });
    notifyListeners();
  }

  /// Ends the recording and sends it.
  Future<void> stopAndSend() async {
    if (!recording || _busy) {
      return;
    }
    _busy = true;
    _end();
    final UploadItem? item = await _recorder.stop();
    _busy = false;
    if (item != null && !_disposed) {
      await _onRecorded(item);
    }
  }

  /// Ends the recording and drops it. Nothing is sent.
  Future<void> cancel() async {
    if (!recording || _busy) {
      return;
    }
    _busy = true;
    _end();
    await _recorder.cancel();
    _busy = false;
  }

  void _end() {
    _timer?.cancel();
    _timer = null;
    recording = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (recording) {
      unawaited(_recorder.cancel());
    }
    super.dispose();
  }
}
