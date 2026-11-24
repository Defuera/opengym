/// The sounds and the vibration of the exercise timer: a short tone when it
/// starts, a tick on each of the last three seconds, a longer tone and a
/// vibration when it ends. The real one plays bundled tones (see
/// audio_timer_cues.dart). Every method returns at once and never throws.
abstract class TimerCues {
  const TimerCues();

  /// The timer started.
  void start();

  /// One of the last three seconds (3, 2, 1).
  void tick();

  /// The time is up: the long tone.
  void end();

  /// The time is up: the vibration.
  void vibrate();
}

/// Does nothing. The default, so tests and plain stores never touch a plugin.
class NoTimerCues extends TimerCues {
  const NoTimerCues();

  @override
  void start() {}

  @override
  void tick() {}

  @override
  void end() {}

  @override
  void vibrate() {}
}
