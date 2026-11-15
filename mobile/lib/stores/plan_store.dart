import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api/open_gym_api.dart';
import '../models.dart';
import '../planner.dart';

/// Start suggestions and the next session plan. The server is tried with a
/// short budget; the local planner is always the fallback.
class PlanStore extends ChangeNotifier {
  PlanStore({
    required OpenGymApi api,
    this.predictionBudget = const Duration(seconds: 2),
    this.planBudget = const Duration(seconds: 12),
  }) : _api = api;

  final OpenGymApi _api;
  final Duration predictionBudget;
  final Duration planBudget;

  /// Server predictions, or empty when none arrived (use [localPredictions]).
  List<Prediction> remote = <Prediction>[];
  bool loadingPredictions = false;
  int _gen = 0;

  Future<void> loadPredictions() async {
    final int gen = ++_gen;
    loadingPredictions = true;
    notifyListeners();
    List<Prediction> got = <Prediction>[];
    try {
      got = await _api.getStart().timeout(predictionBudget);
    } catch (_) {
      got = <Prediction>[];
    }
    if (gen != _gen) {
      return;
    }
    remote = got.where((Prediction p) => p.type.isNotEmpty).toList();
    loadingPredictions = false;
    notifyListeners();
  }

  /// Server list if it answered in time, else the local rotation.
  List<Prediction> predictionsFor(List<Session> sessions) {
    return remote.isNotEmpty ? remote : localPredictions(sessions);
  }

  /// GET /v1/plans/next within [planBudget]. Null on any failure.
  Future<Plan?> fetchNext(String type) async {
    try {
      final Plan p = await _api.nextPlan(type).timeout(planBudget);
      return p.exercises.isEmpty ? null : p;
    } catch (_) {
      return null;
    }
  }

  /// Plan exercises as fresh, not-yet-done session exercises.
  List<Exercise> exercisesFor(Plan plan) {
    return plan.exercises.map((PlanExercise pe) {
      return Exercise(
        id: newId(),
        name: pe.name,
        note: pe.note,
        sets: pe.sets
            .map((PlanSet s) => SetEntry(reps: s.reps, kg: s.kg, isMax: s.max))
            .toList(),
      );
    }).toList();
  }
}

/// The local planner's rotation, in the same shape as the server's.
List<Prediction> localPredictions(List<Session> sessions) {
  final List<Prediction> out = <Prediction>[];
  for (final TypeRank r in predictions(sessions)) {
    out.add(Prediction(
      kind: 'gym',
      type: r.type,
      reason: r.at == 0
          ? 'Not logged yet'
          : 'Last done ${whenLabel(r.at).toLowerCase()}',
    ));
  }
  return out;
}
