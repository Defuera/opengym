import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'screen_awake.dart';

/// [ScreenAwake] on the wakelock_plus package. iOS turns off the idle timer;
/// Android sets the keep-screen-on window flag. Neither needs a permission.
class WakelockScreenAwake extends ScreenAwake {
  const WakelockScreenAwake();

  @override
  Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('screen awake: enable failed: $e');
    }
  }

  @override
  Future<void> disable() async {
    try {
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint('screen awake: disable failed: $e');
    }
  }
}
