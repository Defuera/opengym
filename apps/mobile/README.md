# OpenGym (mobile)

Flutter app for logging gym sessions and other activities. It is offline-first:
everything you log is saved on the phone (shared_preferences) and works with no
server. When a backend is reachable (see `docs/api-contract.md`) the app also
shows live sessions, planned sessions and a dashboard, keeps goals, chats with
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

The backend is hosted Convex (ADR-012). Get the deployment address
(`https://<name>.convex.cloud`) and the app token from the owner.

1. In the app open Settings (gear icon, top right).
2. Enter the Convex URL and the token, then press "Test connection". A wrong
   token or address shows a clear message; it never spins forever.
3. Home says "Connected". Sessions, goals, plans, the dashboard
   and reviews are live subscriptions: the server pushes every change, there
   is no refresh. For test builds, `--dart-define=OPENGYM_URL=...` and
   `--dart-define=OPENGYM_TOKEN=...` set the defaults.

With no connection the app says "Offline: saved on this phone" and keeps
working. Every write (a finished session, goal and note changes) is saved in
a persistent outbox on the phone first. The outbox sends writes in order
through the idempotent Convex commands when connected, survives a restart and
retries on reconnect. Server data never overwrites a change that is still in
the outbox.

Coach chat, file upload and file import also run on Convex. Threads, messages
and import progress are live subscriptions. A chat message shows at once, then
the server copy replaces it (matched by message id); the coach answer arrives
through the subscription while the thread status says `thinking`, `idle` or
`failed`. Chat and import need a connection: they are not queued in the outbox,
and the composer says "Offline" without one. A file upload asks the server for
an upload URL, POSTs the bytes to it and registers the file.

End-to-end check against a deployment: see `tool/convex_trial.dart`.

## Structure

- Domain: `lib/models.dart` (Session, Exercise, SetEntry) re-exports `lib/models/`
  (Plan, Goal, ContextItem, LogEntry + EntryFile, Thread, Message, FileMeta, Prediction,
  DashboardModule, Dashboard, ImportJob, Review). `lib/planner.dart` has the local
  planning rules (pure Dart).
- Data: `lib/data/` has the `SessionRepository`, `SettingsRepository` and
  `OutboxRepository` interfaces with shared_preferences and in-memory
  implementations; `pickers.dart` wraps file_picker and image_picker;
  `upload_item.dart` is a picked local file.
- Gateway: `lib/data/convex_client.dart` is the `ConvexClient` interface (typed
  live streams and idempotent commands) and `DartvexConvexClient`, the only
  code that imports `dartvex`. `switchable_convex_client.dart` lets Settings
  change the address while streams stay open. `convex_codec.dart` maps Convex
  documents to models. Errors shown to the user come from the Convex error
  `.data`, never the raw message.
- Outbox: `outbox.dart` and `outbox_ops.dart` (persistent write queue and the
  overlay that keeps pending changes on top of server data);
  `session_sync.dart` feeds the live session subscription into the local log.
- Stores: `lib/store.dart` (`AppStore`, the live session and local log) and
  `lib/stores/` (`ConnectionStore`, `PlanStore`, `DashboardStore`, `GoalsStore`,
  `ContextStore`, `EntriesStore` (notes), `CoachStore` (chat), `ImportStore` (file import),
  `ReviewStore`, `AboutStore` (limits, body load, after-session questions)). One
  responsibility each, dependencies passed in the constructor.
- About me: the person icon on Home opens `screens/about_me_screen.dart` (body
  figure, limits, preferences = the coach notes). A limit opens
  `limit_detail_screen.dart` (rules, how it felt, own records). After a
  session `AboutStore.askAfter` may show "How was the <limit> today?" on Home
  (`limit_ask_bar.dart`); it never blocks saving and stays silent offline.
  Reads and writes go through `data/about_repository.dart`
  (`ConvexAboutRepository` on the outbox; `InMemoryAboutRepository` for tests).
  The figure is `widgets/body_figure.dart`.
- Notes (log entries): free text with a time, plus photos or files. The plus
  sheet, Log tab, has "Note" as its first choice; it opens
  `screens/entry_form_screen.dart` (text up to 2000 characters, Attach with
  camera / library / file, date and time, Save). `stores/entries_store.dart`
  (`EntriesStore`) subscribes to `queries/entries:recent`, and `save` uploads
  the new files first (`commands/files:generateUploadUrl` + `register`), then
  calls `commands/entries:save`; `remove` calls `commands/entries:remove`. Notes
  need a connection (no outbox); a failed save keeps the form. Home merges
  notes and sessions by time in `screens/home_recent.dart` (`mergeRecent`): a
  note by `at`, a session by its end. On the server dashboard the app list
  replaces the server `recent_sessions` module when notes exist. A tap opens
  `screens/entry_screen.dart` (full text, photos, files, Edit, Delete).
- Composition: `lib/app/compose.dart` is the only place that picks real
  implementations; `lib/app/deps.dart` bundles them for the screens.
- Widgets: `lib/widgets/` are standalone. They import only Flutter, `theme.dart`
  and each other, and take plain values and callbacks.
- Screens: `lib/screens/` are thin. They read stores, map models to widget props
  and pass store methods as callbacks. `dashboard_view.dart` holds the
  module type -> widget map.
- Gallery: `lib/gallery/` is a dependency-free widget gallery. Add a story with
  one entry in `lib/gallery/stories.dart`.
- Tests: `test/` (plain flutter_test): planner, store, model JSON, gateway,
  outbox, connection, live stores. `test/support/fake_convex_client.dart` fakes
  the gateway.
- `tool/patch_ios_plist.sh`: iOS permission and networking keys.

## Widget gallery

```
flutter run -t lib/gallery_main.dart
```
