/// Strict data schema. JSON keys match the web prototype (`max` for isMax).
/// `toJson` is the local persistence shape; `toContractJson` is the API shape.
library;
export 'models/chat.dart';
export 'models/dashboard.dart';
export 'models/goal.dart';
export 'models/misc.dart';
export 'models/plan.dart';

/// The activity name of every gym session. The flavour (Upper, Legs, ...) is
/// the session's `focus` (ADR-013).
const String gymType = 'Gym';

class SetEntry {
  SetEntry({
    required this.reps,
    required this.kg,
    this.isMax = false,
    this.failed = false,
    this.done = false,
    this.at,
  });

  int reps;
  double kg;
  bool isMax;

  /// One more rep was tried after [reps] and not completed.
  bool failed;
  bool done;
  int? at;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> m = <String, dynamic>{
      'reps': reps,
      'kg': kg,
      'max': isMax,
      'done': done,
    };
    if (failed) {
      m['failed'] = true;
    }
    if (at != null) {
      m['at'] = at;
    }
    return m;
  }

  /// API shape: {reps, kg, max, at?}.
  Map<String, dynamic> toContractJson() {
    final Map<String, dynamic> m = <String, dynamic>{
      'reps': reps.clamp(0, 100).toInt(),
      'kg': kg.clamp(0.0, 500.0).toDouble(),
      'max': isMax,
    };
    if (failed) {
      m['failed'] = true;
    }
    if (at != null) {
      m['at'] = at;
    }
    return m;
  }

  factory SetEntry.fromJson(Map<String, dynamic> j) {
    final Object? rawDone = j['done'];
    final Object? rawAt = j['at'];
    return SetEntry(
      reps: (j['reps'] as num).toInt(),
      kg: (j['kg'] as num).toDouble(),
      isMax: j['max'] == true,
      failed: j['failed'] == true,
      // Saved sessions only hold completed sets, so a missing flag means done.
      done: rawDone == null ? true : rawDone == true,
      at: rawAt is num ? rawAt.toInt() : null,
    );
  }
}

class Exercise {
  Exercise({
    required this.id,
    required this.name,
    required this.sets,
    this.fresh = false,
    this.carry = false,
    this.note,
  });

  String id;
  String name;
  List<SetEntry> sets;
  bool fresh;
  bool carry;

  /// Plan note for this exercise (local only, not part of the API shape).
  String? note;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'sets': sets.map((SetEntry s) => s.toJson()).toList(),
      'fresh': fresh,
      'carry': carry,
      if (note != null) 'note': note,
    };
  }

  /// API shape: {name, sets}.
  Map<String, dynamic> toContractJson() {
    final String n = name.length > 60 ? name.substring(0, 60) : name;
    return <String, dynamic>{
      'name': n,
      'sets': sets.take(12).map((SetEntry s) => s.toContractJson()).toList(),
    };
  }

  factory Exercise.fromJson(Map<String, dynamic> j) {
    final List<SetEntry> list = <SetEntry>[];
    final Object? raw = j['sets'];
    if (raw is List) {
      for (final Object? e in raw) {
        list.add(SetEntry.fromJson(e as Map<String, dynamic>));
      }
    }
    return Exercise(
      id: (j['id'] as String?) ?? '',
      name: j['name'] as String,
      sets: list,
      fresh: j['fresh'] == true,
      carry: j['carry'] == true,
      note: j['note'] is String ? j['note'] as String : null,
    );
  }
}

class Session {
  Session({
    required this.id,
    required this.kind,
    required this.type,
    this.focus,
    required this.startedAt,
    this.endedAt,
    List<Exercise>? exercises,
    this.minutes,
    this.distanceKm,
    this.note,
    this.source = 'app',
    this.importId,
    this.planNote,
  }) : exercises = exercises ?? <Exercise>[];

  String id;

  /// 'gym' or 'activity'.
  String kind;

  /// The activity: 'Gym' for kind gym, else 'Run', 'Cycle', ...
  String type;

  /// The flavour of this session ('Upper', 'Legs', 'Easy', ...), or null.
  /// The AI advises it; the user may change it; the app writes it.
  String? focus;
  int startedAt;
  int? endedAt;
  List<Exercise> exercises;
  int? minutes;
  double? distanceKm;
  String? note;

  /// 'app' or 'import'.
  String source;
  String? importId;

  /// Rationale of the plan this session started from (local only).
  String? planNote;

  int get when => endedAt ?? startedAt;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> m = <String, dynamic>{
      'id': id,
      'kind': kind,
      'type': type,
      'startedAt': startedAt,
      'exercises': exercises.map((Exercise e) => e.toJson()).toList(),
    };
    if (focus != null) {
      m['focus'] = focus;
    }
    if (endedAt != null) {
      m['endedAt'] = endedAt;
    }
    if (minutes != null) {
      m['minutes'] = minutes;
    }
    if (distanceKm != null) {
      m['distanceKm'] = distanceKm;
    }
    if (note != null) {
      m['note'] = note;
    }
    m['source'] = source;
    if (importId != null) {
      m['importId'] = importId;
    }
    if (planNote != null) {
      m['planNote'] = planNote;
    }
    return m;
  }

  /// API shape (see docs/api-contract.md). Sets are {reps, kg, max, at}.
  Map<String, dynamic> toContractJson() {
    final String t = type.length > 40 ? type.substring(0, 40) : type;
    final bool gym = kind == 'gym';
    final Map<String, dynamic> m = <String, dynamic>{
      'id': id,
      'kind': kind,
      'type': t.isEmpty ? 'Session' : t,
      'startedAt': startedAt,
      'endedAt': when,
      'exercises': gym
          ? exercises.take(15).map((Exercise e) => e.toContractJson()).toList()
          : <Map<String, dynamic>>[],
      'source': source == 'import' ? 'import' : 'app',
    };
    final String? f = focus?.trim();
    if (f != null && f.isNotEmpty) {
      m['focus'] = f.length > 40 ? f.substring(0, 40) : f;
    }
    if (minutes != null) {
      m['minutes'] = minutes;
    }
    if (distanceKm != null) {
      m['distanceKm'] = distanceKm;
    }
    if (note != null) {
      m['note'] = note;
    }
    if (importId != null) {
      m['importId'] = importId;
    }
    return m;
  }

  /// Reads a session. A legacy gym session (type 'Upper', no focus), from
  /// local storage or an old server row, comes back as type 'Gym', focus 'Upper'.
  factory Session.fromJson(Map<String, dynamic> j) {
    final List<Exercise> list = <Exercise>[];
    final Object? raw = j['exercises'];
    if (raw is List) {
      for (final Object? e in raw) {
        list.add(Exercise.fromJson(e as Map<String, dynamic>));
      }
    }
    final Object? ended = j['endedAt'];
    final Object? mins = j['minutes'];
    final Object? dist = j['distanceKm'];
    final String kind = j['kind'] as String;
    String type = j['type'] as String;
    String? focus = j['focus'] is String && (j['focus'] as String).isNotEmpty
        ? j['focus'] as String
        : null;
    if (kind == 'gym' && type != gymType && type.trim().isNotEmpty) {
      focus ??= type.trim().toLowerCase() == gymType.toLowerCase() ? null : type.trim();
      type = gymType;
    }
    return Session(
      id: (j['id'] as String?) ?? '',
      kind: kind,
      type: type,
      focus: focus,
      startedAt: (j['startedAt'] as num).toInt(),
      endedAt: ended is num ? ended.toInt() : null,
      exercises: list,
      minutes: mins is num ? mins.toInt() : null,
      distanceKm: dist is num ? dist.toDouble() : null,
      note: j['note'] is String ? j['note'] as String : null,
      source: j['source'] == 'import' ? 'import' : 'app',
      importId: j['importId'] is String ? j['importId'] as String : null,
      planNote: j['planNote'] is String ? j['planNote'] as String : null,
    );
  }
}
