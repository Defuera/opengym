import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'timer_cues.dart';

/// [TimerCues] on the audioplayers package and the system vibration.
///
/// The audio session mixes with other apps instead of taking over: on iOS the
/// `ambient` category (it mixes with music and follows the silent switch, so
/// a silent phone stays silent); on Android a transient focus that lets other
/// audio duck for the length of the tone. The vibration does not depend on the
/// silent switch. The tones are in assets/sounds, made by tool/make_timer_tones.py.
class AudioTimerCues extends TimerCues {
  AudioTimerCues() {
    unawaited(_setup());
  }

  final AudioPlayer _start = AudioPlayer();
  final AudioPlayer _tick = AudioPlayer();
  final AudioPlayer _end = AudioPlayer();

  Future<void> _setup() async {
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ));
    } catch (e) {
      debugPrint('timer cues: audio setup failed: $e');
    }
  }

  void _play(AudioPlayer p, String asset) {
    unawaited(() async {
      try {
        await p.stop();
        await p.play(AssetSource('sounds/$asset.wav'));
      } catch (e) {
        debugPrint('timer cues: play failed: $e');
      }
    }());
  }

  @override
  void start() => _play(_start, 'timer_start');

  @override
  void tick() => _play(_tick, 'timer_tick');

  @override
  void end() => _play(_end, 'timer_end');

  @override
  void vibrate() {
    unawaited(HapticFeedback.vibrate().catchError((Object _) {}));
  }
}
