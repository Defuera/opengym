import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/stores/countdown_store.dart';

import 'support/fake_timer_cues.dart';

/// A clock the test moves by hand.
class _Clock {
  DateTime t = DateTime(2026, 11, 24, 10);
  DateTime call() => t;
  void add(Duration d) => t = t.add(d);
}

void main() {
  late _Clock clock;
  late FakeTimerCues cues;
  late FakeScreenAwake awake;
  late CountdownStore cd;

  setUp(() {
    clock = _Clock();
    cues = FakeTimerCues();
    awake = FakeScreenAwake();
    cd = CountdownStore(now: clock.call, cues: cues, awake: awake);
  });
  tearDown(() => cd.dispose());

  /// Runs the clock second by second, as the display refresh would.
  void run(int seconds) {
    for (int i = 0; i < seconds; i++) {
      clock.add(const Duration(seconds: 1));
      cd.tick();
    }
  }

  group('sound', () {
    test('a short tone on start; nothing else yet', () {
      cd.start(Object(), 0.5, () {});
      expect(cues.calls, <String>['start']);
    });

    test('one tick on each of the last three seconds, then the end tone and the vibration once', () {
      cd.start(Object(), 0.5, () {});
      run(26); // 4 s left: no tick yet
      expect(cues.count('tick'), 0);
      run(1); // 3 s left
      expect(cues.count('tick'), 1);
      run(1);
      run(1);
      expect(cues.count('tick'), 3); // 3, 2, 1
      run(1); // 0: the end
      cd.tick();
      cd.tick();
      expect(cues.calls, <String>['start', 'tick', 'tick', 'tick', 'end', 'vibrate']);
    });

    test('a refresh inside one second does not tick twice', () {
      cd.start(Object(), 0.5, () {});
      run(27);
      cd.tick();
      cd.tick();
      expect(cues.count('tick'), 1);
    });

    test('nothing after a stop', () {
      cd.start(Object(), 0.5, () {});
      run(10);
      cd.cancel();
      run(40);
      expect(cues.calls, <String>['start']);
    });

    test('nothing after dispose', () {
      final CountdownStore other = CountdownStore(now: clock.call, cues: cues, awake: awake);
      other.start(Object(), 0.5, () {});
      other.dispose();
      cues.calls.clear();
      run(40);
      other.tick();
      expect(cues.calls, isEmpty);
    });

    test('a pause stops the ticks; resume goes on', () {
      cd.start(Object(), 0.5, () {});
      run(20);
      cd.pause();
      clock.add(const Duration(seconds: 60));
      cd.tick();
      expect(cues.count('tick'), 0);
      cd.resume();
      run(9); // 1 s left: ticks at 3, 2, 1
      expect(cues.count('tick'), 3);
      expect(cues.count('vibrate'), 0);
      run(1);
      expect(cues.count('vibrate'), 1);
    });
  });

  group('screen awake', () {
    test('on at start, off when the time is up', () {
      cd.start(Object(), 0.5, () {});
      expect(awake.on, isTrue);
      run(30);
      expect(awake.on, isFalse);
      expect(awake.calls, <String>['enable', 'disable']);
    });

    test('off on stop', () {
      cd.start(Object(), 0.5, () {});
      cd.cancel();
      expect(awake.on, isFalse);
    });

    test('off on a pause, on again on resume', () {
      cd.start(Object(), 0.5, () {});
      cd.pause();
      expect(awake.on, isFalse);
      cd.resume();
      expect(awake.on, isTrue);
    });

    test('off on dispose, never left on', () {
      cd.start(Object(), 0.5, () {});
      cd.dispose();
      expect(awake.on, isFalse);
      // The shared tearDown disposes again: harmless.
      cd = CountdownStore(now: clock.call, cues: cues, awake: awake);
    });

    test('a replaced countdown keeps the lock without a gap', () {
      cd.start(Object(), 0.5, () {});
      cd.start(Object(), 0.5, () {});
      expect(awake.on, isTrue);
      expect(awake.calls, <String>['enable']);
    });

    test('the screen left or in the background lets go; back in front holds again', () {
      final Object screen = Object();
      cd.setScreenVisible(screen, true);
      cd.start(Object(), 0.5, () {});
      expect(awake.on, isTrue);
      cd.setScreenVisible(screen, false);
      expect(awake.on, isFalse);
      cd.setScreenVisible(screen, true);
      expect(awake.on, isTrue);
    });

    test('a new session screen in front of the old one keeps the lock when the old one goes', () {
      final Object a = Object();
      final Object b = Object();
      cd.setScreenVisible(a, true);
      cd.start(Object(), 0.5, () {});
      cd.setScreenVisible(b, true);
      cd.setScreenVisible(a, false);
      expect(awake.on, isTrue);
      cd.setScreenVisible(b, false);
      expect(awake.on, isFalse);
    });

    test('no countdown, no lock, whatever the screens do', () {
      cd.setScreenVisible(Object(), true);
      expect(awake.calls, isEmpty);
    });
  });
}
