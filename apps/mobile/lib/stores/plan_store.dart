import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/convex_client.dart';
import '../models.dart';
import '../planner.dart';
import 'start_run.dart';

/// Start suggestions (a live subscription) and the next session plan. The
/// local planner is always the fallback when the server has not answered.
class PlanStore extends ChangeNotifier {
  PlanStore({
    required ConvexClient client,
    this.planBudget = const Duration(seconds: 3),
    this.startBudget = const Duration(seconds: 20),
  }) : _client = client;

  final ConvexClient _client;

  /// How long "start a session" waits for the plan of a focus.
  final Duration planBudget;

  /// How long a typed "something new" request may take before the app gives up.
  final Duration startBudget;

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
  /// With [today] the coach picks the session: [text] is the wish and the hint is the pick shown.
  StartRun requestStart({
    String? name,
    String? text,
    bool today = false,
    String? hintType,
    String? hintFocus,
  }) =>
      StartRun(
        client: _client,
        name: name,
        text: text,
        today: today,
        hintType: hintType,
        hintFocus: hintFocus,
        budget: startBudget,
      );

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

/// The local planner's ranking, in the same shape as the server's.
List<Prediction> localPredictions(List<Session> sessions) => rankActivities(sessions);
