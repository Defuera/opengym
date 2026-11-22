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

To update an app that is on the phone already, build and install in place:

```
flutter build ios --release
xcrun devicectl device install app --device <device id> build/ios/iphoneos/Runner.app
```

Do not use `flutter install` for an update. It removes the old app first, and
with it everything the app keeps on the phone: the server address and token,
the open session, and changes that were not sent yet (seen on 2026-11-22).
`flutter devices` prints the device id.

## Android

`android/` is generated with
`flutter create . --platforms=android --org io.devartel --project-name opengym`
(application id `io.devartel.opengym`). By hand: `minSdk` 26 (Health Connect),
`MainActivity` extends `FlutterFragmentActivity`, the manifest has `INTERNET`,
read-only Health Connect permissions, the `queries` entry, the
permission-rationale intent filter and the `ViewPermissionUsageActivity` alias
(privacy policy link). Build: `flutter build apk --debug` (needs the Android SDK).

## Trackers

The app reads tracker data from the phone's health store: Apple Health on
iPhone, Health Connect on Android (ADR-019). Read only; no background sync.

- `lib/data/tracker_source.dart`: `TrackerSource` interface, plain models
  (`TrackerWorkout`, `TrackerDay`, `TrackerSnapshot`) and `FakeTrackerSource`.
- `lib/data/health_tracker_source.dart`: the real source over the `health`
  plugin. The only file that imports it.
- `lib/data/tracker_mapping.dart`: pure functions (sleep de-duplication,
  average heart rate in a workout, day rows).
- `lib/screens/tracker_screen.dart`: Settings, Trackers. Shows sources,
  workouts and days of the last 7 days. It reads on open and on "Read again".
  Nothing is sent to the server yet.
- iOS: `ios/Runner/Runner.entitlements` (HealthKit), set as
  `CODE_SIGN_ENTITLEMENTS` for all Runner configurations;
  `NSHealthShareUsageDescription` in `Info.plist`. The HealthKit capability must
  also be on the App ID in the developer account for a signed device build.

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
- Log by text (ADR-018): an activity from the Log tab list, "Something new" or
  a time/distance type in the Start list opens `screens/log_text_screen.dart`:
  the activity name, one text field ("What did you do?", up to 1000 characters)
  and "Log" (off while empty). `AppStore.logText` saves the session at once
  (`kind` activity, the text as its note, `parse` pending) and `onTextLogged`
  queues the outbox op `session.logText`, which calls
  `commands/sessions:logText` when online (so it works offline and survives a
  restart; the local copy wins while the op waits). The recap opens at once and
  shows "Reading your text…" while `Session.parse` is `pending`; the server's
  `parse_log` job fills minutes, distance, focus, exercises and the day, and
  the live session subscription updates the open recap. A user edit clears
  `parse` locally and on the server. The Start tab's last row is "Something
  else" (not "Other", which can be the name of an activity in the log).
- Session recap and edit: a tap on a finished session (Home "Recent", and the end
  of Finish session) opens `screens/session_recap_screen.dart`: activity, focus,
  date, start and duration (hidden for `source` "import", its times are not
  real), every exercise with all its sets (`widgets/recap_exercise_card.dart`,
  words in `session_text.dart`), the note, the coach review of that session
  (its own `ReviewStore`, the card without a close button) and the body figure
  coloured by what that session loaded (`SessionLoadStore`, query
  `queries/sessions:load`; no figure offline). Edit opens
  `screens/session_edit_screen.dart`: sets, add and remove a set or an exercise
  (the exercise picker), note, focus, date, start time and duration; an activity
  session edits minutes, distance, note and date. It reuses `SetList` and
  `TimeList` through `session_edit_parts.dart` and starts no timer, rest clock
  or active session. Save calls `AppStore.updateSession` (same id; `kind`,
  `source`, `importId` unchanged), which sends the session through the outbox
  like a new one (`onSessionEdited`: no review card on Home, no limit question).
  Leaving with changes asks first. Delete asks in a sheet, then
  `AppStore.removeSession`. Home draws its own Recent list whenever there are
  sessions or notes, because the server list has no session ids.
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
- `tool/patch_ios_plist.sh`: iOS permission and networking keys. It does not add the HealthKit key; that one is already in `Info.plist`.

## Widget gallery

```
flutter run -t lib/gallery_main.dart
```
