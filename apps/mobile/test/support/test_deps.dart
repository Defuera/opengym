import 'dart:async';

import 'package:opengym/app/deps.dart';
import 'package:opengym/data/about_repository.dart';
import 'package:opengym/data/in_memory_about_repository.dart';
import 'package:opengym/data/in_memory_session_repository.dart';
import 'package:opengym/data/outbox.dart';
import 'package:opengym/data/pickers.dart';
import 'package:opengym/data/settings_repository.dart';
import 'package:opengym/data/tracker_prefs.dart';
import 'package:opengym/data/tracker_source.dart';
import 'package:opengym/data/tracker_sync.dart';
import 'package:opengym/data/tracker_writer.dart';
import 'package:opengym/data/voice_recorder.dart';
import 'package:opengym/data/switchable_convex_client.dart';
import 'package:opengym/models.dart';
import 'package:opengym/store.dart';
import 'package:opengym/stores/about_store.dart';
import 'package:opengym/stores/ai_model_store.dart';
import 'package:opengym/stores/coach_store.dart';
import 'package:opengym/stores/connection_store.dart';
import 'package:opengym/stores/context_store.dart';
import 'package:opengym/stores/dashboard_store.dart';
import 'package:opengym/stores/entries_store.dart';
import 'package:opengym/stores/exercise_art_store.dart';
import 'package:opengym/stores/goals_store.dart';
import 'package:opengym/stores/import_store.dart';
import 'package:opengym/stores/places_store.dart';
import 'package:opengym/stores/plan_store.dart';
import 'package:opengym/stores/program_store.dart';
import 'package:opengym/stores/review_store.dart';

import 'fake_convex_client.dart';

/// All app stores on top of [fake], for screen tests. [connected] sets the
/// link state the screens read.
Future<AppDeps> testDeps(
  FakeConvexClient fake, {
  bool connected = true,
  List<Session> sessions = const <Session>[],
  TrackerSource? tracker,
  Pickers? pickers,
  VoiceRecorder? voice,
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
  // As compose wires it: an activity logged as one text goes to the outbox.
  store.onSessionPlaceChanged = (String id, String? placeId) => unawaited(outbox.setSessionPlace(id, placeId));
  store.onTextLogged = (String id) => unawaited(outbox.logText(store.sessionById(id)!));
  final AboutRepository aboutRepo = InMemoryAboutRepository();
  final TrackerSource trackerSource = tracker ?? FakeTrackerSource();
  final TrackerSettings trackerSettings = TrackerSettings(InMemoryTrackerPrefs());
  return AppDeps(
    client: fake,
    store: store,
    connection: connection,
    outbox: outbox,
    plans: PlanStore(client: fake),
    dashboard: DashboardStore(client: fake),
    goals: GoalsStore(client: fake, outbox: outbox),
    entries: EntriesStore(client: fake, isConnected: () => connected)..start(),
    context: ContextStore(client: fake, outbox: outbox),
    coach: CoachStore(client: fake, isConnected: () => connected),
    imports: ImportStore(client: fake),
    reviews: ReviewStore(client: fake),
    pickers: pickers ?? NoPickers(),
    voice: voice ?? NoVoiceRecorder(),
    about: AboutStore(repo: aboutRepo),
    aiModel: AiModelStore(client: fake)..start(),
    tracker: trackerSource,
    trackerSync: TrackerSync(source: trackerSource, client: fake, settings: trackerSettings, isConnected: () => connected),
    trackerWriter: TrackerWriter(source: trackerSource, settings: trackerSettings),
    places: PlacesStore(client: fake)..start(),
    art: ExerciseArtStore(client: fake, isConnected: () => connected),
    programs: ProgramStore(client: fake)..start(),
  );
}
