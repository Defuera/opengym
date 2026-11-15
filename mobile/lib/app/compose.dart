import 'dart:async';

import '../data/api/http_open_gym_api.dart';
import '../data/api/open_gym_api.dart';
import '../data/pickers.dart';
import '../data/settings_repository.dart';
import '../data/shared_prefs_session_repository.dart';
import '../data/sync_service.dart';
import '../data/sync_state_repository.dart';
import '../store.dart';
import '../stores/coach_store.dart';
import '../stores/connection_store.dart';
import '../stores/dashboard_store.dart';
import '../stores/goals_store.dart';
import '../stores/import_store.dart';
import '../stores/plan_store.dart';
import '../stores/review_store.dart';
import 'deps.dart';

/// The one place that picks real implementations. To swap one (say, a fake
/// API for a demo), change it here and nowhere else.
Future<AppDeps> compose() async {
  final OpenGymApi api = HttpOpenGymApi();
  final AppStore store = AppStore(SharedPrefsSessionRepository());
  await store.load();

  final SyncService sync = SyncService(
    api: api,
    state: SharedPrefsSyncStateRepository(),
    store: store,
  );
  final ConnectionStore connection = ConnectionStore(
    settings: SharedPrefsSettingsRepository(),
    api: api,
  );
  final DashboardStore dashboard = DashboardStore(api: api);
  final ReviewStore reviews = ReviewStore(api: api);

  // A finished session: push it, then look for its review and a fresh dashboard.
  store.onSessionSaved = (String id) {
    sync.enqueue(id).then((bool pushed) {
      if (pushed) {
        dashboard.refresh();
        reviews.watch(id);
      } else {
        connection.markOffline();
      }
    });
  };
  reviews.onArrived = dashboard.refresh;
  connection.onConnected = () async {
    await sync.sync(full: true);
  };

  final AppDeps deps = AppDeps(
    store: store,
    connection: connection,
    sync: sync,
    plans: PlanStore(api: api),
    dashboard: dashboard,
    goals: GoalsStore(api: api),
    coach: CoachStore(api: api),
    imports: ImportStore(api: api, sync: sync),
    reviews: reviews,
    pickers: DevicePickers(),
  );

  // Do not wait for the network: the app opens straight away.
  unawaited(connection.load());
  return deps;
}
