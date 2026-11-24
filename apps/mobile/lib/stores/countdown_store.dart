import 'dart:async';

import 'package:flutter/foundation.dart';
import '../data/countdown_signal.dart';
import '../data/screen_awake.dart';
import '../data/timer_cues.dart';

/// The countdown of one time entry in a running session. One at a time.
///
/// It is wall-clock based: it keeps the end time and shows `end - now`. The
/// periodic timer only refreshes the display, so the time stays right after
/// the phone was locked. The state lives here, outside any widget, so it
/// survives rebuilds and leaving the session screen.
///
/// [AppStore] owns one and cancels it when its entry goes away, its minutes
/// change, or it is marked done.
class CountdownStore extends ChangeNotifier {
  CountdownStore({
    DateTime Function()? now,
    this.signal = const NoCountdownSignal(),
    this.cues = const NoTimerCues(),
    this.awake = const NoScreenAwake(),
    this.refresh = const Duration(milliseconds: 200),
  }) : _now = now ?? DateTime.now;

  /// The sound at the end time: a notification planned while the countdown runs.
  final CountdownSignal signal;

  /// The start tone, the ticks of the last three seconds, the end tone and the
  /// vibration. They play while the app runs; in the background the notification
  /// of [signal] is the sound.
  final TimerCues cues;

  /// Keeps the screen on while the countdown runs and the session screen shows.
  final ScreenAwake awake;

  final DateTime Function() _now;
  final Set<Object> _viewers = <Object>{};
  bool _screenSeen = false;
  bool _awakeOn = false;

  /// How often the display refreshes while the countdown runs.
  final Duration refresh;

  Object? _entry;
  double _minutes = 0;
  DateTime? _end;
  Duration _left = Duration.zero;
  bool _paused = false;
  VoidCallback? _onDone;
  String _title = '';
  Timer? _timer;
  int _shownSeconds = 0;

  /// The entry the countdown belongs to, or null when none is active.
  Object? get entry => _entry;

  /// The minutes the entry had when the countdown started.
  double get startMinutes => _minutes;
  bool get active => _entry != null;
  bool get paused => _paused;
  bool isFor(Object entry) => identical(_entry, entry);

  /// Time left; zero when none is active.
  Duration get remaining {
    if (_entry == null) {
      return Duration.zero;
    }
    if (_paused) {
      return _left;
    }
    final Duration d = _end!.difference(_now());
    return d.isNegative ? Duration.zero : d;
  }

  /// Starts a countdown for [entry] from [minutes]. A running one is replaced.
  /// [onDone] runs once when the time is up, after the countdown has ended.
  void start(Object entry, double minutes, VoidCallback onDone, {String title = ''}) {
    _stopTimer();
    _entry = entry;
    _minutes = minutes;
    _left = Duration(milliseconds: (minutes * 60000).round());
    _end = _now().add(_left);
    _paused = false;
    _onDone = onDone;
    _title = title;
    _shownSeconds = _seconds(_left);
    _timer = Timer.periodic(refresh, (Timer _) => tick());
    _plan();
    cues.start();
    _syncAwake();
    notifyListeners();
  }

  /// A session screen ([owner]) is in front (true) or was left or went to the
  /// background (false). The countdown goes on; only the screen lock is let go
  /// when no session screen shows. Before any screen reports, the store counts
  /// as visible, so a store with no screen still holds the lock.
  void setScreenVisible(Object owner, bool visible) {
    _screenSeen = true;
    if (visible) {
      _viewers.add(owner);
    } else {
      _viewers.remove(owner);
    }
    _syncAwake();
  }

  /// The one place that drives the screen lock from the running state: held
  /// while a countdown runs (not paused) and the session screen shows.
  void _syncAwake() {
    final bool want = _entry != null && !_paused && (!_screenSeen || _viewers.isNotEmpty);
    if (want == _awakeOn) {
      return;
    }
    _awakeOn = want;
    unawaited((want ? awake.enable() : awake.disable()).catchError((Object _) {}));
  }

  void pause() {
    if (_entry == null || _paused) {
      return;
    }
    _left = remaining;
    _paused = true;
    _stopTimer();
    _unplan();
    _syncAwake();
    notifyListeners();
  }

  void resume() {
    if (_entry == null || !_paused) {
      return;
    }
    _end = _now().add(_left);
    _paused = false;
    _timer = Timer.periodic(refresh, (Timer _) => tick());
    _shownSeconds = _seconds(_left);
    _plan();
    _syncAwake();
    notifyListeners();
  }

  /// Stops the countdown. Nothing happens to the entry.
  void cancel() {
    if (_entry == null) {
      return;
    }
    _unplan();
    _clear();
    notifyListeners();
  }

  /// Checks the clock: completes when the end time has passed, else refreshes
  /// the display when the shown second changed. Also call it on app resume.
  void tick() {
    if (_entry == null || _paused) {
      return;
    }
    final Duration left = remaining;
    if (left <= Duration.zero) {
      final VoidCallback? done = _onDone;
      _clear();
      notifyListeners();
      cues.end();
      cues.vibrate();
      done?.call();
      return;
    }
    final int s = _seconds(left);
    if (s != _shownSeconds) {
      _shownSeconds = s;
      if (s >= 1 && s <= 3) {
        cues.tick();
      }
      notifyListeners();
    }
  }

  void _plan() {
    unawaited(signal.schedule(at: _end!, title: _title).catchError((Object _) {}));
  }

  void _unplan() {
    unawaited(signal.cancel().catchError((Object _) {}));
  }

  void _clear() {
    _stopTimer();
    _entry = null;
    _end = null;
    _onDone = null;
    _paused = false;
    _left = Duration.zero;
    _syncAwake();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  // At zero the notification has fired by itself: it is not cancelled.

  static int _seconds(Duration d) => (d.inMilliseconds / 1000).ceil();

  @override
  void dispose() {
    _stopTimer();
    _entry = null;
    _syncAwake(); // never leave the screen held
    super.dispose();
  }
}
