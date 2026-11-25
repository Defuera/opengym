import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/transcript_result.dart';
import '../data/voice_recorder.dart';

/// The state of one voice recording in the composer (ADR-034): recording (the
/// seconds so far and the recent loudness), then transcribing, then the text
/// goes to [onText] for the person to check and send. Nothing reaches the
/// coach from here. When the text cannot be read the recording is kept, with a
/// short [note], so [retry] can try the same recording again.
/// It stops by itself at [maxSeconds].
class VoiceController extends ChangeNotifier {
  VoiceController({
    required VoiceRecorder recorder,
    required Future<TranscriptResult> Function(UploadItem item) transcribe,
    required void Function(String text) onText,
    Future<void> Function(UploadItem item)? onDiscard,
    this.maxSeconds = 180,
  })  : _recorder = recorder,
        _transcribe = transcribe,
        _onText = onText,
        _onDiscard = onDiscard;

  final VoiceRecorder _recorder;
  final Future<TranscriptResult> Function(UploadItem item) _transcribe;
  final void Function(String text) _onText;
  final Future<void> Function(UploadItem item)? _onDiscard;
  final int maxSeconds;

  /// How many recent levels are kept for the wave.
  static const int maxLevels = 64;

  bool recording = false;
  int seconds = 0;

  /// The text is being fetched.
  bool transcribing = false;

  /// Recent loudness, 0..1, oldest first, newest last.
  final List<double> levels = <double>[];

  /// Short quiet line for the composer, else null.
  String? note;

  /// A recording the server could not read: [retry] tries it again.
  UploadItem? _held;
  bool get canRetry => _held != null && !transcribing && !recording;

  Timer? _timer;
  StreamSubscription<double>? _levelSub;
  bool _busy = false;
  bool _disposed = false;
  int _run = 0; // the transcription run that counts; cancel makes it stale

  static const String deniedNote = 'Allow the microphone in Settings to record.';
  static const String failedNote = 'Could not start the recording.';
  static const String lostNote = 'Could not read the recording.';

  Future<void> start() async {
    if (recording || _busy || transcribing) {
      return;
    }
    _busy = true;
    await _dropHeld();
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
    levels.clear();
    _levelSub = _recorder.levels.listen((double v) {
      levels.add(v.clamp(0.0, 1.0));
      if (levels.length > maxLevels) {
        levels.removeRange(0, levels.length - maxLevels);
      }
      notifyListeners();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      seconds++;
      if (seconds >= maxSeconds) {
        stopAndTranscribe();
      }
      notifyListeners();
    });
    notifyListeners();
  }

  /// Ends the recording and asks for its text.
  Future<void> stopAndTranscribe() async {
    if (!recording || _busy) {
      return;
    }
    _busy = true;
    _end();
    final UploadItem? item = await _recorder.stop();
    _busy = false;
    if (_disposed) {
      return;
    }
    if (item == null) {
      note = lostNote;
      notifyListeners();
      return;
    }
    await _read(item);
  }

  /// Tries the kept recording again.
  Future<void> retry() async {
    final UploadItem? item = _held;
    if (item == null || transcribing || recording) {
      return;
    }
    await _read(item);
  }

  Future<void> _read(UploadItem item) async {
    final int run = ++_run;
    _held = item;
    transcribing = true;
    note = null;
    notifyListeners();
    TranscriptResult r;
    try {
      r = await _transcribe(item);
    } catch (_) {
      r = const TranscriptResult.failed('Could not reach the server.');
    }
    if (_disposed || run != _run) {
      return; // cancelled meanwhile: cancel already dropped the recording
    }
    transcribing = false;
    final String? text = r.text;
    if (text != null) {
      _held = null;
      note = null;
      _onText(text);
    } else {
      note = '$lostNote ${r.reason ?? ''}'.trim();
    }
    notifyListeners();
  }

  /// Drops the recording (while it runs, while the text is fetched, or when it
  /// was kept after a failure). Nothing is sent.
  Future<void> cancel() async {
    if (recording && !_busy) {
      _busy = true;
      _end();
      await _recorder.cancel();
      _busy = false;
      return;
    }
    if (transcribing || _held != null) {
      _run++; // the answer of a run in flight is not used
      transcribing = false;
      note = null;
      await _dropHeld();
      notifyListeners();
    }
  }

  Future<void> _dropHeld() async {
    final UploadItem? item = _held;
    _held = null;
    note = null;
    if (item != null) {
      await _onDiscard?.call(item);
    }
  }

  void _end() {
    _timer?.cancel();
    _timer = null;
    unawaited(_levelSub?.cancel());
    _levelSub = null;
    recording = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_levelSub?.cancel());
    if (recording) {
      unawaited(_recorder.cancel());
    }
    super.dispose();
  }
}
