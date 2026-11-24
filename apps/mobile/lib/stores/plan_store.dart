import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../models.dart';
import '../planner.dart';
import 'start_run.dart';

/// Start requests and the next session plan. The local planner is always the
/// fallback when the server has not answered.
class PlanStore extends ChangeNotifier {
  PlanStore({
    required ConvexClient client,
    this.planBudget = const Duration(seconds: 3),
    this.startBudget = const Duration(seconds: 40),
  }) : _client = client;

  final ConvexClient _client;

  /// How long "start a session" waits for the plan of a focus.
  final Duration planBudget;

  /// How long a typed "something new" request may take before the app gives up.
  final Duration startBudget;

  /// The plan for [activity] (null: Gym) and [focus] (null: the server's
  /// advised focus): the first answer of the live plan query within
  /// [planBudget]. It reads a stored plan; the server never calls the AI here.
  /// Null on any failure or an empty plan.
  Future<Plan?> fetchNext({String? activity, String? focus}) async {
    try {
      final Stored<Plan> p =
          await _client.watchNextPlan(activity: activity, focus: focus).first.timeout(planBudget);
      return p.value.exercises.isEmpty ? null : p.value;
    } catch (_) {
      return null;
    }
  }

  /// Sends a start request (a fixed [name] and an optional wish [text]) and
  /// watches it. The request is not a fact: it never goes to the outbox. See [StartRun].
  StartRun requestStart({String? name, String? text}) =>
      StartRun(client: _client, name: name, text: text, budget: startBudget);

  /// The exercises of [plan] as fresh, not-yet-done session exercises.
  List<Exercise> exercisesFor(Plan plan) => exercisesOf(plan.exercises);

  /// Plan exercises as fresh, not-yet-done session exercises.
  List<Exercise> exercisesOf(List<PlanExercise> list) {
    return list.map((PlanExercise pe) {
      return Exercise(
        id: newId(),
        name: pe.name,
        note: pe.note,
        measure: pe.measure == measureTime ? measureTime : measureSets,
        sets: pe.sets.map((PlanSet s) {
          final double? min = s.minutes;
          if (pe.measure == measureTime) {
            return SetEntry.time(min ?? 10, distanceKm: s.distanceKm);
          }
          return SetEntry(reps: s.reps, kg: s.kg, isMax: s.max);
        }).toList(),
      );
    }).toList();
  }
}
