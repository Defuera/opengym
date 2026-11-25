import '../data/convex_client.dart';
import '../data/pickers.dart';
import '../data/tracker_source.dart';
import '../data/tracker_sync.dart';
import '../data/tracker_writer.dart';
import '../data/voice_recorder.dart';
import '../data/outbox.dart';
import '../store.dart';
import '../stores/about_store.dart';
import '../stores/ai_model_store.dart';
import '../stores/coach_store.dart';
import '../stores/connection_store.dart';
import '../stores/context_store.dart';
import '../stores/dashboard_store.dart';
import '../stores/entries_store.dart';
import '../stores/exercise_art_store.dart';
import '../stores/goals_store.dart';
import '../stores/import_store.dart';
import '../stores/places_store.dart';
import '../stores/plan_store.dart';
import '../stores/program_store.dart';
import '../stores/review_store.dart';

/// Everything the screens need, created once in compose.dart.
class AppDeps {
  const AppDeps({
    required this.client,
    required this.store,
    required this.connection,
    required this.outbox,
    required this.plans,
    required this.dashboard,
    required this.goals,
    required this.entries,
    required this.context,
    required this.coach,
    required this.imports,
    required this.reviews,
    required this.pickers,
    required this.voice,
    required this.about,
    required this.aiModel,
    required this.tracker,
    required this.trackerSync,
    required this.trackerWriter,
    required this.places,
    required this.art,
    required this.programs,
  });

  /// The gateway, for screens that follow one record (the session recap).
  final ConvexClient client;
  final AppStore store;
  final ConnectionStore connection;
  final Outbox outbox;
  final PlanStore plans;
  final DashboardStore dashboard;
  final GoalsStore goals;
  final EntriesStore entries;
  final ContextStore context;
  final CoachStore coach;
  final ImportStore imports;
  final ReviewStore reviews;
  final Pickers pickers;

  /// The microphone for voice messages in the chat.
  final VoiceRecorder voice;
  final AboutStore about;
  final AiModelStore aiModel;

  /// The phone's health store (ADR-019, ADR-036).
  final TrackerSource tracker;

  /// Sends tracker readings to the server when the person turned reading on.
  final TrackerSync trackerSync;

  /// Writes finished sessions to the health store when the person turned it on.
  final TrackerWriter trackerWriter;

  /// The places the coach knows (read only).
  final PlacesStore places;

  /// Exercise pictures (read only; the server makes them).
  final ExerciseArtStore art;

  /// The programs of the person (live, read only).
  final ProgramStore programs;

}
