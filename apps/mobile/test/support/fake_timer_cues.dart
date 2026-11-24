import 'package:opengym/data/screen_awake.dart';
import 'package:opengym/data/timer_cues.dart';

/// Records the cues in order: 'start', 'tick', 'end', 'vibrate'.
class FakeTimerCues extends TimerCues {
  final List<String> calls = <String>[];

  int count(String c) => calls.where((String x) => x == c).length;

  @override
  void start() => calls.add('start');

  @override
  void tick() => calls.add('tick');

  @override
  void end() => calls.add('end');

  @override
  void vibrate() => calls.add('vibrate');
}

/// Records enable and disable, and whether the screen is held now.
class FakeScreenAwake extends ScreenAwake {
  final List<String> calls = <String>[];
  bool on = false;

  @override
  Future<void> enable() async {
    calls.add('enable');
    on = true;
  }

  @override
  Future<void> disable() async {
    calls.add('disable');
    on = false;
  }
}
