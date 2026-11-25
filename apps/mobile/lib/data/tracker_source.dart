/// Tracker data from the phone's health store (Apple Health or Health
/// Connect), behind an interface, so stores, screens and tests never touch the
/// plugin. Plain Dart models only: no plugin type leaves `data/`.
abstract class TrackerSource {
  /// False when the phone has no health store to read from.
  Future<bool> available();

  /// Asks the user for read permission: workouts, sleep, heart rate, resting
  /// heart rate, steps, active energy and distance. Never asks to write.
  /// True when the system dialog finished without an error. On iPhone this
  /// does not say whether the user allowed reading; the system hides that.
  Future<bool> connect();

  /// What the phone has between [from] and [to]. Throws
  /// [TrackerPermissionException] when the phone says reading is not allowed.
  Future<TrackerSnapshot> read({required DateTime from, required DateTime to});
}

/// Reading is not allowed. The user has to press Connect and allow it.
class TrackerPermissionException implements Exception {
  const TrackerPermissionException();

  @override
  String toString() => 'Reading is not allowed.';
}

class TrackerWorkout {
  const TrackerWorkout({
    required this.id,
    required this.type,
    required this.start,
    required this.end,
    required this.minutes,
    required this.source,
    this.distanceKm,
    this.energyKcal,
    this.avgHeartRate,
  });

  final String id;

  /// Plain words such as "Running".
  final String type;
  final DateTime start;
  final DateTime end;
  final int minutes;
  final double? distanceKm;
  final double? energyKcal;

  /// Mean of the heart rate samples inside the workout, in beats per minute.
  final int? avgHeartRate;

  /// Name of the app or device that wrote the workout.
  final String source;
}

/// One calendar day (local time). A field is null when the phone has nothing.
class TrackerDay {
  const TrackerDay({
    required this.date,
    this.sleepMinutes,
    this.sleepLightMinutes,
    this.sleepDeepMinutes,
    this.sleepRemMinutes,
    this.restingHeartRate,
    this.steps,
    this.activeEnergyKcal,
  });

  /// Midnight of the day, local time.
  final DateTime date;

  /// Minutes asleep in the night that ends on this date.
  final int? sleepMinutes;

  /// Minutes of the night in each stage, when the phone has stages.
  final int? sleepLightMinutes;
  final int? sleepDeepMinutes;
  final int? sleepRemMinutes;
  final int? restingHeartRate;
  final int? steps;

  /// Active energy of the day, in kilocalories.
  final double? activeEnergyKcal;
}

class TrackerSnapshot {
  const TrackerSnapshot({
    this.workouts = const <TrackerWorkout>[],
    this.days = const <TrackerDay>[],
    this.sources = const <String>[],
  });

  /// Newest first.
  final List<TrackerWorkout> workouts;

  /// Newest first. Only days with at least one value.
  final List<TrackerDay> days;

  /// Distinct names of the apps and devices that wrote data, sorted.
  final List<String> sources;

  bool get isEmpty => workouts.isEmpty && days.isEmpty;
}

/// For tests and the gallery: returns what it is given.
class FakeTrackerSource implements TrackerSource {
  FakeTrackerSource({
    this.isAvailable = true,
    this.connectResult = true,
    this.snapshot = const TrackerSnapshot(),
    this.error,
  });

  bool isAvailable;
  bool connectResult;
  TrackerSnapshot snapshot;

  /// Thrown by [read] when set.
  Object? error;
  int connectCalls = 0;
  int readCalls = 0;

  @override
  Future<bool> available() async => isAvailable;

  @override
  Future<bool> connect() async {
    connectCalls++;
    return connectResult;
  }

  @override
  Future<TrackerSnapshot> read({required DateTime from, required DateTime to}) async {
    readCalls++;
    final Object? e = error;
    if (e != null) {
      throw e;
    }
    return snapshot;
  }
}
