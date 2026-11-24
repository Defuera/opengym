/// Keeps the phone screen on. The real one is the wakelock_plus package (see
/// wakelock_screen_awake.dart); it needs no permission on iOS or Android.
abstract class ScreenAwake {
  const ScreenAwake();

  /// Keeps the screen on until [disable]. Never throws.
  Future<void> enable();

  /// Lets the screen sleep again. Never throws.
  Future<void> disable();
}

/// Does nothing. The default, so tests and plain stores never touch a plugin.
class NoScreenAwake extends ScreenAwake {
  const NoScreenAwake();

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}
