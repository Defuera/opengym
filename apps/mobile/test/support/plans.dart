import 'package:opengym/models.dart';
import 'package:opengym/planner.dart';

/// A four-exercise plan for tests. The app has no starter templates, so a test
/// that needs exercises passes them as the prepared plan.
List<Exercise> pushPlan() => <String>[
      'Bench press',
      'Overhead press',
      'Dips',
      'Triceps pushdown',
    ].map((String n) => makeExercise(<Session>[], n)).toList();
