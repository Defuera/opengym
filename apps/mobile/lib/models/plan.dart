import 'json_util.dart';

class PlanSet {
  const PlanSet({required this.reps, required this.kg, this.max = false});

  final int reps;
  final double kg;
  final bool max;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'reps': reps, 'kg': kg, 'max': max};
  }

  factory PlanSet.fromJson(Map<String, dynamic> j) {
    return PlanSet(
      reps: intOf(j['reps']),
      kg: dblOf(j['kg']),
      max: j['max'] == true,
    );
  }
}

class PlanExercise {
  const PlanExercise({required this.name, required this.sets, this.note});

  final String name;
  final List<PlanSet> sets;
  final String? note;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> m = <String, dynamic>{
      'name': name,
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
      exercises: asList(j['exercises'])
          .map((Object? e) => PlanExercise.fromJson(asMap(e)))
          .toList(),
    );
  }
}
