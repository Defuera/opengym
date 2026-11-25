import 'dart:io' show Platform;

import 'package:health/health.dart';

import 'tracker_daily.dart';
import 'tracker_mapping.dart';
import 'tracker_source.dart';

/// Reads Apple Health (iPhone) and Health Connect (Android) through the
/// `health` plugin. One code path; only the list of types differs. It reads
/// without asking to write. [connectWrite] and [writeWorkout] are for the
/// "Write my sessions to Health" switch only (ADR-036).
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

  /// What a write needs. Android: the exercise session and its distance record
  /// (`writeWorkoutData` inserts both). iPhone: the workout type only; the
  /// distance is a property of the workout.
  static List<HealthDataType> get writeTypes => <HealthDataType>[
        HealthDataType.WORKOUT,
        if (Platform.isAndroid) HealthDataType.DISTANCE_DELTA,
      ];

  @override
  Future<bool> connectWrite() async {
    await _configure();
    final List<HealthDataType> types = writeTypes;
    return _health.requestAuthorization(
      types,
      permissions: List<HealthDataAccess>.filled(types.length, HealthDataAccess.WRITE),
    );
  }

  @override
  Future<bool> writeWorkout(WorkoutWrite w) async {
    await _configure();
    final double? km = w.distanceKm;
    return _health.writeWorkoutData(
      activityType: workoutActivityType(w.kind, android: Platform.isAndroid),
      start: w.start,
      end: w.end,
      // The plugin takes whole metres. It takes no sets, reps, weights or heart rate.
      totalDistance: km == null || km <= 0 ? null : (km * 1000).round(),
      title: w.title,
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
    final List<HealthDataPoint> energy = await _get(<HealthDataType>[HealthDataType.ACTIVE_ENERGY_BURNED], first, end);
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
    List<TrackerSpan> spans(Iterable<HealthDataPoint> pts, [HealthDataType? only]) => pts
        .where((HealthDataPoint p) => only == null || p.type == only)
        .map((HealthDataPoint p) => TrackerSpan(p.dateFrom, p.dateTo))
        .toList();
    return TrackerSnapshot(
      workouts: buildWorkouts(workoutPoints.map(_workout).toList(), hrSamples),
      days: buildDays(
        from: first,
        to: last,
        sleep: sleepMinutesByDay(spans(sleep)),
        sleepStages: sleepStagesByDay(
          asleep: spans(sleep),
          light: spans(sleep, HealthDataType.SLEEP_LIGHT),
          deep: spans(sleep, HealthDataType.SLEEP_DEEP),
          rem: spans(sleep, HealthDataType.SLEEP_REM),
        ),
        activeEnergy: activeEnergyByDay(energy.map(_energy).toList()),
        restingHeartRate: resting.map(_sample).toList(),
        steps: steps,
      ),
      sources: distinctSources(<HealthDataPoint>[...workoutPoints, ...hr, ...resting, ...sleep].map((HealthDataPoint p) => p.sourceName)),
    );
  }

  Future<List<HealthDataPoint>> _get(List<HealthDataType> types, DateTime start, DateTime end) {
    return _health.getHealthDataFromTypes(types: types, startTime: start, endTime: end);
  }

  /// The plugin reports active energy in kilocalories (its default unit for the type).
  EnergyReading _energy(HealthDataPoint p) {
    final HealthValue v = p.value;
    return EnergyReading(
      start: p.dateFrom,
      kcal: v is NumericHealthValue ? v.numericValue.toDouble() : 0,
      source: p.sourceId.isEmpty ? p.sourceName : p.sourceId,
    );
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
      sourceId: p.sourceId,
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

/// The plugin's activity type for [kind] on this platform. The type names
/// differ: iPhone has no STRENGTH_TRAINING and no SWIMMING_POOL; Android has
/// no TRADITIONAL_STRENGTH_TRAINING and its map has no plain SWIMMING (read in
/// `HealthConstants.kt` and `SwiftHealthPlugin.swift`, health 13.3.1).
HealthWorkoutActivityType workoutActivityType(WorkoutKind kind, {required bool android}) {
  switch (kind) {
    case WorkoutKind.strength:
      return android ? HealthWorkoutActivityType.STRENGTH_TRAINING : HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING;
    case WorkoutKind.running:
      return HealthWorkoutActivityType.RUNNING;
    case WorkoutKind.walking:
      return HealthWorkoutActivityType.WALKING;
    case WorkoutKind.cycling:
      return HealthWorkoutActivityType.BIKING;
    case WorkoutKind.swimming:
      return android ? HealthWorkoutActivityType.SWIMMING_POOL : HealthWorkoutActivityType.SWIMMING;
    case WorkoutKind.hiking:
      return HealthWorkoutActivityType.HIKING;
    case WorkoutKind.rowing:
      return HealthWorkoutActivityType.ROWING;
    case WorkoutKind.yoga:
      return HealthWorkoutActivityType.YOGA;
    case WorkoutKind.other:
      return HealthWorkoutActivityType.OTHER;
  }
}
