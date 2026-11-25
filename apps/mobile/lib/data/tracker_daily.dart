import 'tracker_mapping.dart';

/// More pure functions for tracker days: sleep stages, active energy and the
/// filter for workouts that Gym Days wrote itself (ADR-036).

/// The id Gym Days has in the health store: the Android package name and the
/// iOS bundle id are the same (`applicationId` in `android/app/build.gradle.kts`,
/// `PRODUCT_BUNDLE_IDENTIFIER` in the iOS project).
const String ownSourceId = 'io.devartel.opengym';

/// True when a store entry was written by this app. Read from `sourceId` of
/// the plugin point: the Android package name or the iOS bundle id. The plugin
/// cannot set a metadata marker on a workout it writes, so the source is the
/// only mark. A debug or flavour build keeps the id as a prefix.
bool isOwnSource(String sourceId) => sourceId == ownSourceId || sourceId.startsWith('$ownSourceId.');

/// Minutes in each sleep stage of one night. A stage is null when the phone
/// holds no span of it.
class SleepStages {
  const SleepStages({this.light, this.deep, this.rem});

  final int? light;
  final int? deep;
  final int? rem;

  bool get isEmpty => light == null && deep == null && rem == null;
}

/// Stage minutes per night, keyed like [sleepMinutesByDay] (the date the night
/// ends on). A night is found from every "asleep" span, as there. Each stage
/// span is merged with spans of its own stage, clipped to the night, and
/// summed. [asleep] is every span of every stage.
Map<DateTime, SleepStages> sleepStagesByDay({
  required List<TrackerSpan> asleep,
  List<TrackerSpan> light = const <TrackerSpan>[],
  List<TrackerSpan> deep = const <TrackerSpan>[],
  List<TrackerSpan> rem = const <TrackerSpan>[],
  Duration maxGap = const Duration(hours: 3),
}) {
  final List<TrackerSpan> merged = mergeSpans(asleep);
  final List<TrackerSpan> l = mergeSpans(light);
  final List<TrackerSpan> d = mergeSpans(deep);
  final List<TrackerSpan> r = mergeSpans(rem);
  final Map<DateTime, SleepStages> out = <DateTime, SleepStages>{};
  int i = 0;
  while (i < merged.length) {
    final DateTime start = merged[i].start;
    DateTime end = merged[i].end;
    int j = i + 1;
    while (j < merged.length && merged[j].start.difference(end) < maxGap) {
      end = merged[j].end;
      j++;
    }
    int? within(List<TrackerSpan> spans) {
      int seconds = 0;
      for (final TrackerSpan s in spans) {
        final DateTime a = s.start.isBefore(start) ? start : s.start;
        final DateTime b = s.end.isAfter(end) ? end : s.end;
        if (b.isAfter(a)) {
          seconds += b.difference(a).inSeconds;
        }
      }
      return seconds == 0 ? null : (seconds / 60).round();
    }

    final SleepStages stages = SleepStages(light: within(l), deep: within(d), rem: within(r));
    if (!stages.isEmpty) {
      final DateTime day = dayOf(end);
      final SleepStages? old = out[day];
      out[day] = old == null
          ? stages
          : SleepStages(
              light: _add(old.light, stages.light),
              deep: _add(old.deep, stages.deep),
              rem: _add(old.rem, stages.rem),
            );
    }
    i = j;
  }
  return out;
}

int? _add(int? a, int? b) => a == null ? b : (b == null ? a : a + b);

/// One active-energy reading: kcal over a span, from one app or device.
class EnergyReading {
  const EnergyReading({required this.start, required this.kcal, required this.source});

  final DateTime start;
  final double kcal;
  final String source;
}

/// Active kcal per day (the day the reading starts on). Two sources often
/// write the same energy (a watch and the phone), so a day takes the source
/// with the largest sum, not the sum of all. (Inferred: this avoids counting
/// twice; the plugin has no cross-source merge for energy.)
Map<DateTime, double> activeEnergyByDay(List<EnergyReading> readings) {
  final Map<DateTime, Map<String, double>> sums = <DateTime, Map<String, double>>{};
  for (final EnergyReading r in readings) {
    if (r.kcal <= 0) {
      continue;
    }
    final Map<String, double> bySource = sums.putIfAbsent(dayOf(r.start), () => <String, double>{});
    bySource[r.source] = (bySource[r.source] ?? 0) + r.kcal;
  }
  return <DateTime, double>{
    for (final MapEntry<DateTime, Map<String, double>> e in sums.entries)
      e.key: e.value.values.reduce((double a, double b) => a > b ? a : b),
  };
}
