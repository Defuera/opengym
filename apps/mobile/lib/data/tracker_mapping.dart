import 'tracker_daily.dart';
import 'tracker_source.dart';

/// Pure functions that turn raw samples into the tracker models. No plugin
/// types here, so they are easy to test.

/// A time span, such as a sleep stage or a workout.
class TrackerSpan {
  const TrackerSpan(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

/// One reading, such as a heart rate sample.
class TrackerSample {
  const TrackerSample({required this.at, required this.value});

  final DateTime at;
  final double value;
}

/// A workout as the plugin reports it, before the heart rate is added.
class RawWorkout {
  const RawWorkout({
    required this.id,
    required this.type,
    required this.start,
    required this.end,
    required this.source,
    this.sourceId = '',
    this.distanceKm,
    this.energyKcal,
  });

  final String id;
  final String type;
  final DateTime start;
  final DateTime end;
  final String source;

  /// Package name (Android) or bundle id (iOS) of the writer. Empty when unknown.
  final String sourceId;
  final double? distanceKm;
  final double? energyKcal;
}

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// "TRADITIONAL_STRENGTH_TRAINING" -> "Traditional strength training".
String workoutTypeLabel(String name) {
  if (name.isEmpty) {
    return 'Workout';
  }
  final String words = name.toLowerCase().replaceAll('_', ' ').trim();
  return words[0].toUpperCase() + words.substring(1);
}

/// Merges overlapping or touching spans, so samples from two sources that
/// cover the same minutes count once. The result is sorted.
List<TrackerSpan> mergeSpans(List<TrackerSpan> spans) {
  final List<TrackerSpan> sorted = spans.where((TrackerSpan s) => s.end.isAfter(s.start)).toList()
    ..sort((TrackerSpan a, TrackerSpan b) => a.start.compareTo(b.start));
  final List<TrackerSpan> out = <TrackerSpan>[];
  for (final TrackerSpan s in sorted) {
    if (out.isNotEmpty && !s.start.isAfter(out.last.end)) {
      final TrackerSpan last = out.removeLast();
      out.add(TrackerSpan(last.start, s.end.isAfter(last.end) ? s.end : last.end));
    } else {
      out.add(s);
    }
  }
  return out;
}

/// Minutes asleep per night, keyed by the date the night ends on. [asleep]
/// holds every "asleep" span from every source. Spans that overlap count
/// once. Spans less than [maxGap] apart belong to one night, so a night that
/// crosses midnight is not split.
Map<DateTime, int> sleepMinutesByDay(
  List<TrackerSpan> asleep, {
  Duration maxGap = const Duration(hours: 3),
}) {
  final List<TrackerSpan> merged = mergeSpans(asleep);
  final Map<DateTime, int> out = <DateTime, int>{};
  int i = 0;
  while (i < merged.length) {
    int seconds = merged[i].end.difference(merged[i].start).inSeconds;
    DateTime end = merged[i].end;
    int j = i + 1;
    while (j < merged.length && merged[j].start.difference(end) < maxGap) {
      seconds += merged[j].end.difference(merged[j].start).inSeconds;
      end = merged[j].end;
      j++;
    }
    final DateTime day = dayOf(end);
    out[day] = (out[day] ?? 0) + (seconds / 60).round();
    i = j;
  }
  return out;
}

/// Mean of the samples that fall inside the span, rounded. Null when none.
int? averageInside(DateTime start, DateTime end, List<TrackerSample> samples) {
  double sum = 0;
  int n = 0;
  for (final TrackerSample s in samples) {
    if (!s.at.isBefore(start) && !s.at.isAfter(end)) {
      sum += s.value;
      n++;
    }
  }
  return n == 0 ? null : (sum / n).round();
}

/// Workouts newest first, each with its minutes and its heart rate average.
/// A workout that Gym Days wrote itself is left out ([isOwnSource]): it is a
/// logged session already, not a tracker reading.
List<TrackerWorkout> buildWorkouts(List<RawWorkout> raw, List<TrackerSample> heartRate) {
  final List<TrackerWorkout> out = raw
      .where((RawWorkout w) => !isOwnSource(w.sourceId))
      .map(
        (RawWorkout w) => TrackerWorkout(
          id: w.id,
          type: w.type,
          start: w.start,
          end: w.end,
          minutes: (w.end.difference(w.start).inSeconds / 60).round(),
          distanceKm: w.distanceKm,
          energyKcal: w.energyKcal,
          avgHeartRate: averageInside(w.start, w.end, heartRate),
          source: w.source,
        ),
      )
      .toList()
    ..sort((TrackerWorkout a, TrackerWorkout b) => b.start.compareTo(a.start));
  return out;
}

/// One row per day from [from] to [to] (dates, local), newest first. A day
/// with no value at all gets no row. Resting heart rate of a day is the mean
/// of that day's samples.
List<TrackerDay> buildDays({
  required DateTime from,
  required DateTime to,
  required Map<DateTime, int> sleep,
  required List<TrackerSample> restingHeartRate,
  required Map<DateTime, int> steps,
  Map<DateTime, SleepStages> sleepStages = const <DateTime, SleepStages>{},
  Map<DateTime, double> activeEnergy = const <DateTime, double>{},
}) {
  final Map<DateTime, List<double>> resting = <DateTime, List<double>>{};
  for (final TrackerSample s in restingHeartRate) {
    resting.putIfAbsent(dayOf(s.at), () => <double>[]).add(s.value);
  }
  final List<TrackerDay> out = <TrackerDay>[];
  final DateTime last = dayOf(to);
  for (DateTime d = dayOf(from); !d.isAfter(last); d = DateTime(d.year, d.month, d.day + 1)) {
    final List<double>? r = resting[d];
    final int? rhr = r == null ? null : (r.reduce((double a, double b) => a + b) / r.length).round();
    final int? sl = sleep[d];
    final int? st = steps[d];
    final double? kcal = activeEnergy[d];
    final SleepStages? stages = sleepStages[d];
    if (rhr != null || sl != null || st != null || kcal != null) {
      out.add(TrackerDay(
        date: d,
        sleepMinutes: sl,
        sleepLightMinutes: sl == null ? null : stages?.light,
        sleepDeepMinutes: sl == null ? null : stages?.deep,
        sleepRemMinutes: sl == null ? null : stages?.rem,
        restingHeartRate: rhr,
        steps: st,
        activeEnergyKcal: kcal,
      ));
    }
  }
  return out.reversed.toList();
}

/// Distinct names, sorted, without blanks.
List<String> distinctSources(Iterable<String> names) {
  final List<String> out = names.map((String n) => n.trim()).where((String n) => n.isNotEmpty).toSet().toList()..sort();
  return out;
}

/// "7 h 20 min", "45 min", "2 h".
String formatMinutes(int minutes) {
  final int h = minutes ~/ 60;
  final int m = minutes % 60;
  if (h == 0) {
    return '$m min';
  }
  return m == 0 ? '$h h' : '$h h $m min';
}
