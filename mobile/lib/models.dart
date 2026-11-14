/// Strict data schema. JSON keys match the web prototype (`max` for isMax).
class SetEntry {
  SetEntry({
    required this.reps,
    required this.kg,
    this.isMax = false,
    this.done = false,
    this.at,
  });

  int reps;
  double kg;
  bool isMax;
  bool done;
  int? at;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> m = <String, dynamic>{
      'reps': reps,
      'kg': kg,
      'max': isMax,
      'done': done,
    };
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
  });

  String id;
  String name;
  List<SetEntry> sets;
  bool fresh;
  bool carry;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'sets': sets.map((SetEntry s) => s.toJson()).toList(),
      'fresh': fresh,
      'carry': carry,
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
    );
  }
}

class Session {
  Session({
    required this.id,
    required this.kind,
    required this.type,
    required this.startedAt,
    this.endedAt,
    List<Exercise>? exercises,
    this.minutes,
  }) : exercises = exercises ?? <Exercise>[];

  String id;

  /// 'gym' or 'activity'.
  String kind;
  String type;
  int startedAt;
  int? endedAt;
  List<Exercise> exercises;
  int? minutes;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> m = <String, dynamic>{
      'id': id,
      'kind': kind,
      'type': type,
      'startedAt': startedAt,
      'exercises': exercises.map((Exercise e) => e.toJson()).toList(),
    };
    if (endedAt != null) {
      m['endedAt'] = endedAt;
    }
    if (minutes != null) {
      m['minutes'] = minutes;
    }
    return m;
  }

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
    return Session(
      id: (j['id'] as String?) ?? '',
      kind: j['kind'] as String,
      type: j['type'] as String,
      startedAt: (j['startedAt'] as num).toInt(),
      endedAt: ended is num ? ended.toInt() : null,
      exercises: list,
      minutes: mins is num ? mins.toInt() : null,
    );
  }
}
