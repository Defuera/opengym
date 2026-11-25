import 'tracker_source.dart';

/// The wire shape of `commands/tracker:sync` (docs/api-contract.md, ADR-036).
/// A field the phone has no value for is left out, so the server row holds
/// only what was read.

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, dynamic> trackerDayJson(TrackerDay d) => <String, dynamic>{
      'date': _date(d.date),
      if (d.sleepMinutes != null) 'sleepMinutes': d.sleepMinutes,
      if (d.sleepLightMinutes != null) 'sleepLightMinutes': d.sleepLightMinutes,
      if (d.sleepDeepMinutes != null) 'sleepDeepMinutes': d.sleepDeepMinutes,
      if (d.sleepRemMinutes != null) 'sleepRemMinutes': d.sleepRemMinutes,
      if (d.restingHeartRate != null) 'restingHeartRate': d.restingHeartRate,
      if (d.steps != null) 'steps': d.steps,
      if (d.activeEnergyKcal != null) 'activeEnergyKcal': d.activeEnergyKcal,
    };

Map<String, dynamic> trackerWorkoutJson(TrackerWorkout w) => <String, dynamic>{
      'workoutId': w.id,
      'type': w.type,
      'startedAt': w.start.millisecondsSinceEpoch,
      'endedAt': w.end.millisecondsSinceEpoch,
      'minutes': w.minutes,
      if (w.distanceKm != null) 'distanceKm': w.distanceKm,
      if (w.energyKcal != null) 'energyKcal': w.energyKcal,
      if (w.avgHeartRate != null) 'avgHeartRate': w.avgHeartRate,
      'sourceName': w.source.isEmpty ? 'unknown' : w.source,
    };

/// The server caps one call at this many days and workouts.
const int trackerDaysMax = 31;
const int trackerWorkoutsMax = 100;
