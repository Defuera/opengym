import 'dart:async';

import '../data/about_repository.dart';
import '../data/convex_client.dart';
import '../data/legacy_outbox_migration.dart';
import '../data/outbox.dart';
import '../data/health_tracker_source.dart';
import '../data/local_countdown_signal.dart';
import '../data/pickers.dart';
import '../data/voice_recorder.dart';
import '../data/open_session_sync.dart';
import '../data/session_sync.dart';
import '../data/settings_repository.dart';
import '../data/shared_prefs_session_repository.dart';
import '../data/switchable_convex_client.dart';
import '../store.dart';
import '../stores/about_store.dart';
import '../stores/ai_model_store.dart';
import '../stores/coach_store.dart';
import '../stores/connection_store.dart';
import '../stores/context_store.dart';
import '../stores/countdown_store.dart';
import '../stores/dashboard_store.dart';
import '../stores/entries_store.dart';
import '../stores/goals_store.dart';
import '../stores/import_store.dart';
import '../stores/exercise_art_store.dart';
import '../stores/places_store.dart';
import '../stores/plan_store.dart';
import '../stores/program_store.dart';
import '../stores/review_store.dart';
import 'deps.dart';

/// The one place that picks real implementations. To swap one (say, a fake
/// gateway for a demo), change it here and nowhere else.
Future<AppDeps> compose() async {
  final SwitchableConvexClient client = SwitchableConvexClient(
    (String url, String token) => DartvexConvexClient.connect(url: url, token: token),
  );
  final AppStore store = AppStore(
    SharedPrefsSessionRepository(),
    countdown: CountdownStore(signal: LocalCountdownSignal()),
  );
  await store.load();

  late final ConnectionStore connection;
  final Outbox outbox = Outbox(
    repo: SharedPrefsOutboxRepository(),
    client: client,
    isConnected: () => connection.connected,
  );
  await outbox.load();
  connection = ConnectionStore(
    settings: SharedPrefsSettingsRepository(),
    client: client,
  );
  final SessionSync sessions = SessionSync(client: client, store: store, outbox: outbox);
  // The open session: saved on the phone first, then kept the same on the server (ADR-028).
  final OpenSessionSync openSession =
      OpenSessionSync(client: client, store: store, isConnected: () => connection.connected);
  connection.onConnected = () {
    unawaited(outbox.flush());
    unawaited(openSession.flush());
  };

  final DashboardStore dashboard = DashboardStore(client: client);
  final CoachStore coach = CoachStore(client: client, isConnected: () => connection.connected);
  final ReviewStore reviews = ReviewStore(client: client);
  final PlanStore plans = PlanStore(client: client);
  final GoalsStore goals = GoalsStore(client: client, outbox: outbox);
  final EntriesStore entries = EntriesStore(client: client, isConnected: () => connection.connected);
  final ContextStore context = ContextStore(client: client, outbox: outbox);
  final ImportStore imports = ImportStore(client: client);
  final AiModelStore aiModel = AiModelStore(client: client);
  final PlacesStore places = PlacesStore(client: client);
  final ExerciseArtStore art = ExerciseArtStore(client: client, isConnected: () => connection.connected);
  final ProgramStore programs = ProgramStore(client: client);
  final AboutStore about = AboutStore(repo: ConvexAboutRepository(client: client, outbox: outbox));

  // A finished session goes to the outbox on disk first, then to the server.
  store.onSessionSaved = (String id) {
    final session = store.sessionById(id);
    if (session != null) {
      // After the session is on the server, ask how the loaded limits felt.
      // A failure or no link means no question; saving is never held up.
      unawaited(outbox.saveSession(session).then((_) => about.askAfter(id)));
      reviews.watch(id);
    }
  };
  // An activity logged as one text: the text goes to the outbox on disk first; the server reads it into the session.
  store.onTextLogged = (String id) {
    final session = store.sessionById(id);
    if (session != null) {
      unawaited(outbox.logText(session).then((_) => about.askAfter(id)));
      reviews.watch(id);
    }
  };
  // A corrected past session: same id, same save path. No review card, no question.
  store.onSessionEdited = (String id) {
    final session = store.sessionById(id);
    if (session != null) {
      unawaited(outbox.saveSession(session));
    }
  };
  store.onSessionPlaceChanged = (String id, String? placeId) => unawaited(outbox.setSessionPlace(id, placeId));
  store.onSessionRemoved = (String id) => unawaited(outbox.removeSession(id));
  imports.onUndone = store.removeImported;

  // Live subscriptions: opened once, they survive a change of server address.
  sessions.start();
  openSession.start();
  goals.start();
  entries.start();
  context.start();
  about.start();
  aiModel.start();
  places.start();
  programs.start();
  coach.start();
  imports.watchPast();
  dashboard.select(7);

  final AppDeps deps = AppDeps(
    client: client,
    store: store,
    connection: connection,
    outbox: outbox,
    plans: plans,
    dashboard: dashboard,
    goals: goals,
    entries: entries,
    context: context,
    coach: coach,
    imports: imports,
    reviews: reviews,
    pickers: DevicePickers(),
    voice: DeviceVoiceRecorder(),
    about: about,
    aiModel: aiModel,
    tracker: HealthTrackerSource(),
    places: places,
    art: art,
    programs: programs,
  );

  // Do not wait for the network: the app opens straight away.
  unawaited(() async {
    await migrateLegacyOutbox(store, outbox);
    await connection.load();
  }());
  return deps;
}
