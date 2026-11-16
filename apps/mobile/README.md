# OpenGym (mobile)

Flutter app for logging gym sessions and other activities. It is offline-first:
everything you log is saved on the phone (shared_preferences) and works with no
server. When a backend is reachable (see `docs/api-contract.md`) the app also
syncs sessions, shows planned sessions and a dashboard, keeps goals, chats with
the coach and imports files and photos.

**Warning: this code was written without a compiler. Run `flutter analyze`
first and fix anything it reports before anything else.**

## Install on an iPhone

1. `cd apps/mobile && flutter create . --platforms=ios --org io.devartel --project-name opengym`
   (generates `ios/`, keeps `lib/`)
2. `tool/patch_ios_plist.sh` (adds local-network http, camera and photo
   permissions to `ios/Runner/Info.plist`; macOS only, safe to re-run;
   the http setting is for development)
3. `flutter pub get`
4. `flutter analyze`
5. `flutter test`
6. `open ios/Runner.xcworkspace` -> Runner target -> Signing & Capabilities ->
   pick your team
7. Plug in the iPhone (Developer Mode on) -> `flutter run --release`

## First run with the backend

1. Start the backend on your computer. It prints its address and the app token.
2. Put the phone and the computer on the same wifi.
3. In the app open Settings (gear icon, top right).
4. Enter the server URL and the token, then press "Test connection". It shows
   the AI provider and whether AI is configured.
5. Home now says "Connected". Finished sessions sync in the background; the
   dashboard, goals, chat and import work against the server.

With no server the app says "Offline: saved on this phone" and keeps working.
Finished sessions wait in a local outbox and are sent when the server is back.

## Structure

- Domain: `lib/models.dart` (Session, Exercise, SetEntry) re-exports `lib/models/`
  (Plan, Goal, ContextItem, Thread, Message, FileMeta, Prediction,
  DashboardModule, Dashboard, ImportJob, Review). `lib/planner.dart` has the local
  planning rules (pure Dart).
- Data: `lib/data/` has the `SessionRepository`, `SettingsRepository` and
  `SyncStateRepository` interfaces with shared_preferences and in-memory
  implementations; `pickers.dart` wraps file_picker and image_picker;
  `sync_service.dart` is the outbox and pull-merge.
- API: `lib/data/api/` has the `OpenGymApi` interface (one method per endpoint),
  `HttpOpenGymApi` (via `ApiTransport`: Bearer token, timeouts, one
  `ApiException`) and `FakeOpenGymApi` for tests.
- Stores: `lib/store.dart` (`AppStore`, the live session and local log) and
  `lib/stores/` (`ConnectionStore`, `PlanStore`, `DashboardStore`, `GoalsStore`,
  `CoachStore`, `ImportStore`, `ReviewStore`). One responsibility each,
  dependencies passed in the constructor.
- Composition: `lib/app/compose.dart` is the only place that picks real
  implementations; `lib/app/deps.dart` bundles them for the screens.
- Widgets: `lib/widgets/` are standalone. They import only Flutter, `theme.dart`
  and each other, and take plain values and callbacks.
- Screens: `lib/screens/` are thin. They read stores, map models to widget props
  and pass store methods as callbacks. `dashboard_view.dart` holds the
  module type -> widget map.
- Gallery: `lib/gallery/` is a dependency-free widget gallery. Add a story with
  one entry in `lib/gallery/stories.dart`.
- Tests: `test/` (plain flutter_test): planner, store, model JSON, sync outbox.
- `tool/patch_ios_plist.sh`: iOS permission and networking keys.

## Widget gallery

```
flutter run -t lib/gallery_main.dart
```
