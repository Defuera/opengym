import 'json_util.dart';

/// One planned entry. A set has [reps] and [kg]; an entry of a time exercise
/// has [minutes] and, optionally, [distanceKm].
class PlanSet {
  const PlanSet({
    required this.reps,
    required this.kg,
    this.max = false,
    this.minutes,
    this.distanceKm,
  });

  final int reps;
  final double kg;
  final bool max;
  final double? minutes;
  final double? distanceKm;

  Map<String, dynamic> toJson() {
    final double? min = minutes;
    if (min != null) {
      return <String, dynamic>{
        'minutes': min,
        if (distanceKm != null) 'distanceKm': distanceKm,
      };
    }
    return <String, dynamic>{'reps': reps, 'kg': kg, 'max': max};
  }

  factory PlanSet.fromJson(Map<String, dynamic> j) {
    return PlanSet(
      reps: intOf(j['reps']),
      kg: dblOf(j['kg']),
      max: j['max'] == true,
      minutes: dblOrNull(j['minutes']),
      distanceKm: dblOrNull(j['distanceKm']),
    );
  }
}

class PlanExercise {
  const PlanExercise({
    required this.name,
    required this.sets,
    this.note,
    this.measure = 'sets',
  });

  final String name;

  /// 'sets' (default) or 'time'.
  final String measure;
  final List<PlanSet> sets;
  final String? note;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> m = <String, dynamic>{
      'name': name,
      if (measure == 'time') 'measure': 'time',
      'sets': sets.map((PlanSet s) => s.toJson()).toList(),
    };
    if (note != null) {
      m['note'] = note;
    }
    return m;
  }

  factory PlanExercise.fromJson(Map<String, dynamic> j) {
    return PlanExercise(
      name: str(j['name']),
      measure: j['measure'] == 'time' ? 'time' : 'sets',
      sets: asList(j['sets'])
          .map((Object? e) => PlanSet.fromJson(asMap(e)))
          .toList(),
      note: strOrNull(j['note']),
    );
  }
}

class Plan {
  const Plan({
    required this.id,
    required this.focus,
    required this.createdAt,
    required this.source,
    required this.rationale,
    required this.exercises,
  });

  final String id;
  /// The focus this plan is for ('Upper', 'Legs', ...). May be empty.
  final String focus;
  final int createdAt;

  /// 'ai' or 'rules'.
  final String source;
  final String rationale;
  final List<PlanExercise> exercises;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': 'Gym',
      'focus': focus,
      'createdAt': createdAt,
      'source': source,
      'rationale': rationale,
      'exercises': exercises.map((PlanExercise e) => e.toJson()).toList(),
    };
  }

  factory Plan.fromJson(Map<String, dynamic> j) {
    return Plan(
      id: str(j['id']),
      focus: str(j['focus']),
      createdAt: intOf(j['createdAt']),
      source: str(j['source'], 'rules'),
      rationale: str(j['rationale']),
      exercises: _readable(asList(j['exercises'])),
    );
  }

  /// An exercise this build cannot read (a newer shape from the server) is
  /// left out; the rest of the plan is kept.
  static List<PlanExercise> _readable(List<Object?> raw) {
    final List<PlanExercise> out = <PlanExercise>[];
    for (final Object? e in raw) {
      try {
        out.add(PlanExercise.fromJson(asMap(e)));
      } catch (_) {
        // skip
      }
    }
    return out;
  }
}
