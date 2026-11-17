import 'package:opengym/app/deps.dart';
import 'package:opengym/data/about_repository.dart';
import 'package:opengym/data/in_memory_about_repository.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/data/outbox.dart';
import 'package:opengym/data/pickers.dart';
import 'package:opengym/data/settings_repository.dart';
import 'package:opengym/data/switchable_convex_client.dart';
import 'package:opengym/models.dart';
import 'package:opengym/store.dart';
import 'package:opengym/stores/about_store.dart';
import 'package:opengym/stores/coach_store.dart';
import 'package:opengym/stores/connection_store.dart';
import 'package:opengym/stores/context_store.dart';
import 'package:opengym/stores/dashboard_store.dart';
import 'package:opengym/stores/goals_store.dart';
import 'package:opengym/stores/import_store.dart';
import 'package:opengym/stores/plan_store.dart';
import 'package:opengym/stores/review_store.dart';

import 'fake_convex_client.dart';

/// All app stores on top of [fake], for screen tests. [connected] sets the
/// link state the screens read.
Future<AppDeps> testDeps(
  FakeConvexClient fake, {
  bool connected = true,
  List<Session> sessions = const <Session>[],
}) async {
  final InMemorySessionRepository repo = InMemorySessionRepository();
  final AppStore store = AppStore(repo);
  await store.load();
  store.sessions.addAll(sessions);
  final ConnectionStore connection = ConnectionStore(
    settings: InMemorySettingsRepository(),
    client: SwitchableConvexClient((String url, String token) => fake),
  )..state = connected ? ConnState.connected : ConnState.offline;
  final Outbox outbox = Outbox(
    repo: InMemoryOutboxRepository(),
    client: fake,
    isConnected: () => connected,
    retryAfter: const Duration(hours: 1),
  );
  final AboutRepository aboutRepo = InMemoryAboutRepository();
  return AppDeps(
    store: store,
    connection: connection,
    outbox: outbox,
    plans: PlanStore(client: fake),
    dashboard: DashboardStore(client: fake),
    goals: GoalsStore(client: fake, outbox: outbox),
    context: ContextStore(client: fake, outbox: outbox),
    coach: CoachStore(client: fake, isConnected: () => connected),
    imports: ImportStore(client: fake),
    reviews: ReviewStore(client: fake),
    pickers: NoPickers(),
    about: AboutStore(repo: aboutRepo),
  );
}
