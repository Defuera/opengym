import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
    void Function()? alert,
    this.refresh = const Duration(milliseconds: 200),
  })  : _now = now ?? DateTime.now,
        _alert = alert ?? _deviceAlert;

  final DateTime Function() _now;
  final void Function() _alert;

  /// How often the display refreshes while the countdown runs.
  final Duration refresh;

  Object? _entry;
  double _minutes = 0;
  DateTime? _end;
  Duration _left = Duration.zero;
  bool _paused = false;
  VoidCallback? _onDone;
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
  void start(Object entry, double minutes, VoidCallback onDone) {
    _stopTimer();
    _entry = entry;
    _minutes = minutes;
    _left = Duration(milliseconds: (minutes * 60000).round());
    _end = _now().add(_left);
    _paused = false;
    _onDone = onDone;
    _shownSeconds = _seconds(_left);
    _timer = Timer.periodic(refresh, (Timer _) => tick());
    notifyListeners();
  }

  void pause() {
    if (_entry == null || _paused) {
      return;
    }
    _left = remaining;
    _paused = true;
    _stopTimer();
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
    notifyListeners();
  }

  /// Stops the countdown. Nothing happens to the entry.
  void cancel() {
    if (_entry == null) {
      return;
    }
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
      _alert();
      done?.call();
      return;
    }
    final int s = _seconds(left);
    if (s != _shownSeconds) {
      _shownSeconds = s;
      notifyListeners();
    }
  }

  void _clear() {
    _stopTimer();
    _entry = null;
    _end = null;
    _onDone = null;
    _paused = false;
    _left = Duration.zero;
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  static int _seconds(Duration d) => (d.inMilliseconds / 1000).ceil();

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}

void _deviceAlert() {
  unawaited(HapticFeedback.heavyImpact().catchError((Object _) {}));
  unawaited(SystemSound.play(SystemSoundType.alert).catchError((Object _) {}));
}
