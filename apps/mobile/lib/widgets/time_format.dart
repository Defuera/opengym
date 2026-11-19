/// How a time entry is shown and stepped. Pure Dart, no imports, so widgets
/// and screens can both use it. The stored value stays `minutes` as a number
/// (30 s is 0.5); only the words change.
library;

/// Whole seconds of [minutes].
int timeSeconds(double minutes) => (minutes * 60).round();

/// Up to this many seconds an entry is edited in 5 s steps.
const int shortTimeSeconds = 120;

/// The lowest value of a time entry, in seconds.
const int minTimeSeconds = 5;

const int _maxTimeSeconds = 600 * 60;

String _clock(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

/// "30 s" (under 60 s), "10 min" (whole minutes) or "1:30 min".
String formatTimeEntry(double minutes) {
  final int s = timeSeconds(minutes);
  if (s < 60) {
    return '$s s';
  }
  return s % 60 == 0 ? '${s ~/ 60} min' : '${_clock(s)} min';
}

/// The big value of the editor: "30" (seconds), "10" (minutes) or "1:30".
String timeValue(double minutes) {
  final int s = timeSeconds(minutes);
  if (s < 60) {
    return '$s';
  }
  return s % 60 == 0 ? '${s ~/ 60}' : _clock(s);
}

/// The unit under the big value: "SEC" under 60 s, else "MIN".
String timeUnit(double minutes) => timeSeconds(minutes) < 60 ? 'SEC' : 'MIN';

/// True when an entry is short (2 minutes or less): no distance is offered.
bool isShortTime(double minutes) => timeSeconds(minutes) <= shortTimeSeconds;

/// The minutes after one step of the minus or plus control. [delta] counts
/// steps: its sign is the direction, 1 is one step and 5 or more a long press.
/// At 2 minutes or less a step is 5 s (long: 30 s, never below 5 s). Above 2
/// minutes a step is 1 minute (long: 5 minutes), never below 2 minutes on the
/// way down and never above 600 minutes. A step that crosses 2 minutes stops there.
double stepMinutes(double minutes, double delta) {
  final int cur = timeSeconds(minutes);
  final bool long = delta.abs() >= 5;
  int next;
  if (delta > 0) {
    next = cur < shortTimeSeconds ? cur + (long ? 30 : 5) : cur + (long ? 300 : 60);
    if (cur < shortTimeSeconds && next > shortTimeSeconds) {
      next = shortTimeSeconds;
    }
  } else if (delta < 0) {
    next = cur <= shortTimeSeconds ? cur - (long ? 30 : 5) : cur - (long ? 300 : 60);
    if (cur > shortTimeSeconds && next < shortTimeSeconds) {
      next = shortTimeSeconds;
    }
  } else {
    next = cur;
  }
  next = next.clamp(minTimeSeconds, _maxTimeSeconds);
  return double.parse((next / 60).toStringAsFixed(4));
}
