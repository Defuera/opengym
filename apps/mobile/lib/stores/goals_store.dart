import 'package:flutter/foundation.dart';

import '../data/api/open_gym_api.dart';
import '../models.dart';

/// Goals live on the server; this store lists and edits them.
class GoalsStore extends ChangeNotifier {
  GoalsStore({required OpenGymApi api}) : _api = api;

  final OpenGymApi _api;

  List<Goal> goals = <Goal>[];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      goals = await _api.listGoals();
      error = null;
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not load goals.';
    }
    loading = false;
    notifyListeners();
  }

  Future<bool> add({
    required String title,
    required String kind,
    String? exercise,
    double? targetKg,
    int? sessionsPerWeek,
  }) {
    return _run(() async {
      final Goal g = await _api.createGoal(
        title: title,
        kind: kind,
        exercise: exercise,
        targetKg: targetKg,
        sessionsPerWeek: sessionsPerWeek,
      );
      goals = <Goal>[...goals, g];
    });
  }

  Future<bool> markDone(Goal goal) {
    return _run(() async {
      final Goal g = await _api.patchGoal(
        goal.id,
        <String, dynamic>{'status': goal.done ? 'active' : 'done'},
      );
      goals = goals.map((Goal x) => x.id == g.id ? g : x).toList();
    });
  }

  Future<bool> remove(Goal goal) {
    return _run(() async {
      await _api.deleteGoal(goal.id);
      goals = goals.where((Goal x) => x.id != goal.id).toList();
    });
  }

  Future<bool> _run(Future<void> Function() body) async {
    try {
      await body();
      error = null;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Something went wrong.';
    }
    notifyListeners();
    return false;
  }
}
