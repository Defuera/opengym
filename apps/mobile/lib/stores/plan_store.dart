import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../models.dart';
import '../planner.dart';

/// Start suggestions (a live subscription) and the next session plan. The
/// local planner is always the fallback when the server has not answered.
class PlanStore extends ChangeNotifier {
  PlanStore({
    required ConvexClient client,
    this.planBudget = const Duration(seconds: 3),
  }) : _client = client;

  final ConvexClient _client;

  /// How long "start a session" waits for the plan of a type.
  final Duration planBudget;

  /// Server predictions, or empty when none arrived (use [localPredictions]).
  List<Prediction> remote = <Prediction>[];

  /// `ai` or `rules`, as the server says.
  String source = 'rules';
  String? error;
  StreamSubscription<Stored<List<Prediction>>>? _sub;

  /// Subscribe once. Updates are pushed; there is no refresh.
  void start() {
    _sub ??= _client.watchPredictions().listen(
      (Stored<List<Prediction>> r) {
        remote = r.value.where((Prediction p) => p.type.isNotEmpty).toList();
        source = r.source;
        error = null;
        notifyListeners();
      },
      onError: (Object e) {
        error = e is ConvexCallException ? e.message : 'Could not load suggestions.';
        notifyListeners();
      },
    );
  }

  /// Server list if it answered, else the local rotation.
  List<Prediction> predictionsFor(List<Session> sessions) {
    return remote.isNotEmpty ? remote : localPredictions(sessions);
  }

  /// The plan for [type]: the first answer of the live plan query within
  /// [planBudget]. Null on any failure or an empty plan.
  Future<Plan?> fetchNext(String type) async {
    try {
      final Stored<Plan> p = await _client.watchNextPlan(type).first.timeout(planBudget);
      return p.value.exercises.isEmpty ? null : p.value;
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
        sets: pe.sets.map((PlanSet s) => SetEntry(reps: s.reps, kg: s.kg, isMax: s.max)).toList(),
      );
    }).toList();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// The local planner's rotation, in the same shape as the server's.
List<Prediction> localPredictions(List<Session> sessions) {
  final List<Prediction> out = <Prediction>[];
  for (final TypeRank r in predictions(sessions)) {
    out.add(Prediction(
      kind: 'gym',
      type: r.type,
      reason: r.at == 0 ? 'Not logged yet' : 'Last done ${whenLabel(r.at).toLowerCase()}',
    ));
  }
  return out;
}
