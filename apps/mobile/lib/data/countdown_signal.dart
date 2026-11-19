/// The sound at the end of a countdown, also when the phone is locked or the
/// app is in the background. The real one is a local notification scheduled
/// for the end time (see local_countdown_signal.dart).
abstract class CountdownSignal {
  const CountdownSignal();

  /// Plans one signal at [at]; [title] is the exercise name. A new call
  /// replaces the planned one. Never throws.
  Future<void> schedule({required DateTime at, required String title});

  /// Removes the planned signal. Never throws.
  Future<void> cancel();
}

/// Does nothing. The default, so tests and plain stores never touch a plugin.
class NoCountdownSignal extends CountdownSignal {
  const NoCountdownSignal();

  @override
  Future<void> schedule({required DateTime at, required String title}) async {}

  @override
  Future<void> cancel() async {}
}
