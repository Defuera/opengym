import 'dart:io' show Platform;

import 'package:health/health.dart';

import 'tracker_mapping.dart';
import 'tracker_source.dart';

/// Reads Apple Health (iPhone) and Health Connect (Android) through the
/// `health` plugin. One code path; only the list of types differs. Read only:
/// it never asks to write and never writes.
class HealthTrackerSource implements TrackerSource {
  HealthTrackerSource({Health? health}) : _health = health ?? Health();

  final Health _health;
  bool _configured = false;

  // Asleep stages only. Awake and in-bed time is not counted as sleep.
  static const List<HealthDataType> _sleepTypes = <HealthDataType>[
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  ];

  /// Workouts, sleep, heart rate, resting heart rate, steps, active energy
  /// and distance. The distance types differ by platform.
  static List<HealthDataType> get permissionTypes => <HealthDataType>[
        HealthDataType.WORKOUT,
        ..._sleepTypes,
        HealthDataType.HEART_RATE,
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.STEPS,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        if (Platform.isIOS) ...<HealthDataType>[
          HealthDataType.DISTANCE_WALKING_RUNNING,
          HealthDataType.DISTANCE_CYCLING,
          HealthDataType.DISTANCE_SWIMMING,
        ] else
          HealthDataType.DISTANCE_DELTA,
      ];

  Future<void> _configure() async {
    if (!_configured) {
      await _health.configure();
      _configured = true;
    }
  }

  @override
  Future<bool> available() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return false;
    }
    try {
      return await _health.isHealthConnectAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> connect() async {
    await _configure();
    final List<HealthDataType> types = permissionTypes;
    return _health.requestAuthorization(
      types,
      permissions: List<HealthDataAccess>.filled(types.length, HealthDataAccess.READ),
    );
  }

  @override
  Future<TrackerSnapshot> read({required DateTime from, required DateTime to}) async {
    await _configure();
    final List<HealthDataType> types = permissionTypes;
    final bool? allowed = await _health.hasPermissions(
      types,
      permissions: List<HealthDataAccess>.filled(types.length, HealthDataAccess.READ),
    );
    // iPhone answers null: Apple hides whether reading is allowed.
    if (allowed == false) {
      throw const TrackerPermissionException();
    }
    final DateTime first = dayOf(from);
    final DateTime last = dayOf(to);
    final DateTime end = DateTime(last.year, last.month, last.day + 1);

    final List<HealthDataPoint> workoutPoints = await _get(<HealthDataType>[HealthDataType.WORKOUT], first, end);
    final List<HealthDataPoint> hr = await _get(<HealthDataType>[HealthDataType.HEART_RATE], first, end);
    final List<HealthDataPoint> resting = await _get(<HealthDataType>[HealthDataType.RESTING_HEART_RATE], first, end);
    // A night that ends on the first day starts the day before.
    final List<HealthDataPoint> sleep = await _get(
      _sleepTypes,
      DateTime(first.year, first.month, first.day - 1),
      end,
    );

    final Map<DateTime, int> steps = <DateTime, int>{};
    final DateTime now = DateTime.now();
    for (DateTime d = first; d.isBefore(end); d = DateTime(d.year, d.month, d.day + 1)) {
      final DateTime dayEnd = DateTime(d.year, d.month, d.day + 1);
      final int? n = await _health.getTotalStepsInInterval(d, dayEnd.isAfter(now) ? now : dayEnd);
      if (n != null && n > 0) {
        steps[d] = n;
      }
    }

    final List<TrackerSample> hrSamples = hr.map(_sample).toList();
    return TrackerSnapshot(
      workouts: buildWorkouts(workoutPoints.map(_workout).toList(), hrSamples),
      days: buildDays(
        from: first,
        to: last,
        sleep: sleepMinutesByDay(sleep.map((HealthDataPoint p) => TrackerSpan(p.dateFrom, p.dateTo)).toList()),
        restingHeartRate: resting.map(_sample).toList(),
        steps: steps,
      ),
      sources: distinctSources(<HealthDataPoint>[...workoutPoints, ...hr, ...resting, ...sleep].map((HealthDataPoint p) => p.sourceName)),
    );
  }

  Future<List<HealthDataPoint>> _get(List<HealthDataType> types, DateTime start, DateTime end) {
    return _health.getHealthDataFromTypes(types: types, startTime: start, endTime: end);
  }

  TrackerSample _sample(HealthDataPoint p) {
    final HealthValue v = p.value;
    return TrackerSample(at: p.dateFrom, value: v is NumericHealthValue ? v.numericValue.toDouble() : 0);
  }

  RawWorkout _workout(HealthDataPoint p) {
    final HealthValue v = p.value;
    String type = 'Workout';
    double? km;
    double? kcal;
    if (v is WorkoutHealthValue) {
      type = workoutTypeLabel(v.workoutActivityType.name);
      km = _km(v.totalDistance, v.totalDistanceUnit);
      kcal = _kcal(v.totalEnergyBurned, v.totalEnergyBurnedUnit);
    }
    return RawWorkout(
      id: p.uuid,
      type: type,
      start: p.dateFrom,
      end: p.dateTo,
      source: p.sourceName,
      distanceKm: km,
      energyKcal: kcal,
    );
  }

  double? _km(int? value, HealthDataUnit? unit) {
    if (value == null || value <= 0) {
      return null;
    }
    switch (unit) {
      case HealthDataUnit.METER:
        return value / 1000;
      case HealthDataUnit.MILE:
        return value * 1.609344;
      case HealthDataUnit.YARD:
        return value * 0.0009144;
      case HealthDataUnit.FOOT:
        return value * 0.0003048;
      default:
        return null;
    }
  }

  double? _kcal(int? value, HealthDataUnit? unit) {
    if (value == null || value <= 0) {
      return null;
    }
    return unit == HealthDataUnit.KILOCALORIE ? value.toDouble() : null;
  }
}
