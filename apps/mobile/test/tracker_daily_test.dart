import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/tracker_daily.dart';
import 'package:opengym/data/tracker_mapping.dart';
import 'package:opengym/data/tracker_source.dart';

DateTime t(int d, int h, [int m = 0]) => DateTime(2026, 11, d, h, m);

void main() {
  group('own writes', () {
    test('the app id and its flavours are own, other ids are not', () {
      expect(isOwnSource('io.devartel.opengym'), isTrue);
      expect(isOwnSource('io.devartel.opengym.debug'), isTrue);
      expect(isOwnSource('com.fitbit.FitbitMobile'), isFalse);
      expect(isOwnSource('io.devartel.opengymx'), isFalse);
      expect(isOwnSource(''), isFalse);
    });

    test('buildWorkouts drops a workout that Gym Days wrote and keeps the others', () {
      final List<TrackerWorkout> w = buildWorkouts(
        <RawWorkout>[
          RawWorkout(id: 'mine', type: 'Strength training', start: t(17, 9), end: t(17, 10), source: 'Gym Days', sourceId: 'io.devartel.opengym'),
          RawWorkout(id: 'fit', type: 'Running', start: t(17, 7), end: t(17, 7, 40), source: 'Fitbit', sourceId: 'com.fitbit.FitbitMobile'),
          RawWorkout(id: 'unknown', type: 'Walking', start: t(16, 7), end: t(16, 8), source: 'Phone'),
        ],
        const <TrackerSample>[],
      );
      expect(w.map((TrackerWorkout x) => x.id), <String>['fit', 'unknown']);
    });
  });

  group('sleep stages', () {
    test('stage minutes go to the night they sit in', () {
      final Map<DateTime, SleepStages> r = sleepStagesByDay(
        asleep: <TrackerSpan>[TrackerSpan(t(16, 23), t(17, 7))],
        light: <TrackerSpan>[TrackerSpan(t(16, 23), t(17, 2)), TrackerSpan(t(17, 4), t(17, 7))],
        deep: <TrackerSpan>[TrackerSpan(t(17, 2), t(17, 3))],
        rem: <TrackerSpan>[TrackerSpan(t(17, 3), t(17, 4))],
      );
      final SleepStages n = r[DateTime(2026, 11, 17)]!;
      expect(n.light, 360);
      expect(n.deep, 60);
      expect(n.rem, 60);
    });

    test('a stage with no span is null; no stages at all gives no row', () {
      final Map<DateTime, SleepStages> r = sleepStagesByDay(
        asleep: <TrackerSpan>[TrackerSpan(t(16, 23), t(17, 7))],
        deep: <TrackerSpan>[TrackerSpan(t(17, 2), t(17, 3))],
      );
      expect(r[DateTime(2026, 11, 17)]!.light, isNull);
      expect(r[DateTime(2026, 11, 17)]!.deep, 60);
      expect(sleepStagesByDay(asleep: <TrackerSpan>[TrackerSpan(t(16, 23), t(17, 7))]), isEmpty);
    });
  });

  group('active energy', () {
    test('a day takes the source with the largest sum, not the sum of all', () {
      final Map<DateTime, double> r = activeEnergyByDay(<EnergyReading>[
        EnergyReading(start: t(17, 8), kcal: 100, source: 'watch'),
        EnergyReading(start: t(17, 12), kcal: 300, source: 'watch'),
        EnergyReading(start: t(17, 9), kcal: 250, source: 'phone'),
        EnergyReading(start: t(18, 9), kcal: 80, source: 'phone'),
        EnergyReading(start: t(18, 10), kcal: 0, source: 'phone'),
      ]);
      expect(r, <DateTime, double>{DateTime(2026, 11, 17): 400, DateTime(2026, 11, 18): 80});
    });
  });

  test('buildDays carries stages and active energy, and a day with only energy still has a row', () {
    final List<TrackerDay> d = buildDays(
      from: t(16, 0),
      to: t(17, 12),
      sleep: <DateTime, int>{DateTime(2026, 11, 17): 480},
      restingHeartRate: const <TrackerSample>[],
      steps: const <DateTime, int>{},
      sleepStages: <DateTime, SleepStages>{DateTime(2026, 11, 17): const SleepStages(light: 360, deep: 60, rem: 60)},
      activeEnergy: <DateTime, double>{DateTime(2026, 11, 16): 220.5},
    );
    expect(d.map((TrackerDay x) => x.date.day), <int>[17, 16]);
    expect(d[0].sleepDeepMinutes, 60);
    expect(d[0].sleepLightMinutes, 360);
    expect(d[1].activeEnergyKcal, 220.5);
    expect(d[1].sleepMinutes, isNull);
  });
}
