import '../data/pickers.dart';
import '../data/outbox.dart';
import '../store.dart';
import '../stores/about_store.dart';
import '../stores/coach_store.dart';
import '../stores/connection_store.dart';
import '../stores/context_store.dart';
import '../stores/dashboard_store.dart';
import '../stores/goals_store.dart';
import '../stores/import_store.dart';
import '../stores/plan_store.dart';
import '../stores/review_store.dart';

/// Everything the screens need, created once in compose.dart.
class AppDeps {
  const AppDeps({
    required this.store,
    required this.connection,
    required this.outbox,
    required this.plans,
    required this.dashboard,
    required this.goals,
    required this.context,
    required this.coach,
    required this.imports,
    required this.reviews,
    required this.pickers,
    required this.about,
  });

  final AppStore store;
  final ConnectionStore connection;
  final Outbox outbox;
  final PlanStore plans;
  final DashboardStore dashboard;
  final GoalsStore goals;
  final ContextStore context;
  final CoachStore coach;
  final ImportStore imports;
  final ReviewStore reviews;
  final Pickers pickers;
  final AboutStore about;
}
