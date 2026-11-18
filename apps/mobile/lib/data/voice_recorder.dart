import 'dart:io';

import 'package:record/record.dart';

import 'upload_item.dart';

export 'upload_item.dart';

/// What happened when a recording was asked to start.
enum VoiceStart { started, denied, failed }

/// The microphone behind an interface, so stores and tests never touch the
/// plugin. One recording at a time. The file is AAC in an .m4a (mime audio/mp4).
abstract class VoiceRecorder {
  /// Asks for the microphone permission when needed, then starts recording.
  Future<VoiceStart> start();

  /// Ends the recording and returns the file, or null when there is none.
  Future<UploadItem?> stop();

  /// Ends the recording and deletes the file.
  Future<void> cancel();
}

/// The real recorder, over the `record` plugin. The only file that imports it.
class DeviceVoiceRecorder implements VoiceRecorder {
  AudioRecorder? _rec;

  @override
  Future<VoiceStart> start() async {
    try {
      final AudioRecorder rec = _rec ??= AudioRecorder();
      if (!await rec.hasPermission()) {
        return VoiceStart.denied;
      }
      final String path = '${Directory.systemTemp.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      // Speech: mono, 16 kHz, 32 kbit/s. Three minutes stay well under 10 MB.
      await rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1, bitRate: 32000),
        path: path,
      );
      return VoiceStart.started;
    } catch (_) {
      return VoiceStart.failed;
    }
  }

  @override
  Future<UploadItem?> stop() async {
    try {
      final String? path = await _rec?.stop();
      if (path == null || !File(path).existsSync()) {
        return null;
      }
      return UploadItem(path: path, name: 'voice.m4a');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _rec?.cancel();
    } catch (_) {}
  }
}

/// For tests and the gallery: the microphone is never available.
class NoVoiceRecorder implements VoiceRecorder {
  @override
  Future<VoiceStart> start() async => VoiceStart.failed;

  @override
  Future<UploadItem?> stop() async => null;

  @override
  Future<void> cancel() async {}
}
