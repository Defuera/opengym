import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/tracker_mapping.dart';
import 'package:opengym/data/tracker_source.dart';

DateTime t(int d, int h, [int m = 0]) => DateTime(2026, 11, d, h, m);

void main() {
  group('sleepMinutesByDay', () {
    test('counts overlapping spans from two sources once', () {
      final Map<DateTime, int> r = sleepMinutesByDay(<TrackerSpan>[
        TrackerSpan(t(16, 23), t(17, 7)), // watch: 8 h
        TrackerSpan(t(16, 23, 30), t(17, 6, 30)), // phone: inside the watch span
        TrackerSpan(t(17, 6), t(17, 7, 20)), // ends later: extends by 20 min
      ]);
      expect(r, <DateTime, int>{DateTime(2026, 11, 17): 8 * 60 + 20});
    });

    test('a night with a break and midnight crossing is one night on the end date', () {
      final Map<DateTime, int> r = sleepMinutesByDay(<TrackerSpan>[
        TrackerSpan(t(16, 23), t(17, 1)),
        TrackerSpan(t(17, 1, 30), t(17, 7)),
      ]);
      expect(r, <DateTime, int>{DateTime(2026, 11, 17): 120 + 330});
    });

    test('a nap is its own cluster and adds to its day', () {
      final Map<DateTime, int> r = sleepMinutesByDay(<TrackerSpan>[
        TrackerSpan(t(17, 0), t(17, 7)),
        TrackerSpan(t(17, 14), t(17, 14, 40)),
        TrackerSpan(t(17, 23), t(18, 6)),
      ]);
      expect(r[DateTime(2026, 11, 17)], 420 + 40);
      expect(r[DateTime(2026, 11, 18)], 420);
    });

    test('empty and zero-length spans give nothing', () {
      expect(sleepMinutesByDay(<TrackerSpan>[]), isEmpty);
      expect(sleepMinutesByDay(<TrackerSpan>[TrackerSpan(t(17, 1), t(17, 1))]), isEmpty);
    });
  });

  group('averageInside', () {
    test('is the mean of the samples inside the span, ends included', () {
      final List<TrackerSample> s = <TrackerSample>[
        TrackerSample(at: t(17, 9, 59), value: 60),
        TrackerSample(at: t(17, 10), value: 100),
        TrackerSample(at: t(17, 10, 30), value: 150),
        TrackerSample(at: t(17, 11), value: 140),
        TrackerSample(at: t(17, 11, 1), value: 70),
      ];
      expect(averageInside(t(17, 10), t(17, 11), s), 130);
    });

    test('is null with no sample inside', () {
      expect(averageInside(t(17, 10), t(17, 11), <TrackerSample>[TrackerSample(at: t(17, 12), value: 80)]), isNull);
    });
  });

  test('buildWorkouts adds minutes and heart rate and sorts newest first', () {
    final List<TrackerWorkout> w = buildWorkouts(
      <RawWorkout>[
        RawWorkout(id: 'a', type: 'Running', start: t(15, 7), end: t(15, 7, 45), source: 'Watch', distanceKm: 6.2),
        RawWorkout(id: 'b', type: 'Cycling', start: t(17, 18), end: t(17, 19), source: 'Phone'),
      ],
      <TrackerSample>[TrackerSample(at: t(15, 7, 10), value: 150), TrackerSample(at: t(15, 7, 20), value: 160)],
    );
    expect(w.map((TrackerWorkout x) => x.id), <String>['b', 'a']);
    expect(w[1].minutes, 45);
    expect(w[1].avgHeartRate, 155);
    expect(w[1].distanceKm, 6.2);
    expect(w[0].avgHeartRate, isNull);
  });

  group('buildDays', () {
    test('one row per day with data, newest first, resting rate is a daily mean', () {
      final List<TrackerDay> d = buildDays(
        from: t(11, 0),
        to: t(17, 15),
        sleep: <DateTime, int>{DateTime(2026, 11, 17): 440},
        restingHeartRate: <TrackerSample>[
          TrackerSample(at: t(15, 8), value: 50),
          TrackerSample(at: t(15, 20), value: 53),
        ],
        steps: <DateTime, int>{DateTime(2026, 11, 15): 8000, DateTime(2026, 11, 13): 1200},
      );
      expect(d.map((TrackerDay x) => x.date.day), <int>[17, 15, 13]);
      expect(d[0].sleepMinutes, 440);
      expect(d[0].steps, isNull);
      expect(d[1].restingHeartRate, 52);
      expect(d[1].steps, 8000);
      expect(d[2].sleepMinutes, isNull);
    });

    test('days outside the range are dropped', () {
      final List<TrackerDay> d = buildDays(
        from: t(15, 0),
        to: t(16, 0),
        sleep: <DateTime, int>{DateTime(2026, 11, 10): 400},
        restingHeartRate: const <TrackerSample>[],
        steps: const <DateTime, int>{},
      );
      expect(d, isEmpty);
    });
  });

  test('small helpers', () {
    expect(workoutTypeLabel('TRADITIONAL_STRENGTH_TRAINING'), 'Traditional strength training');
    expect(workoutTypeLabel(''), 'Workout');
    expect(formatMinutes(440), '7 h 20 min');
    expect(formatMinutes(45), '45 min');
    expect(formatMinutes(120), '2 h');
    expect(distinctSources(<String>['Watch', ' Phone', 'Watch', '']), <String>['Phone', 'Watch']);
  });
}
