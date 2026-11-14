# OpenGym (mobile MVP)

A small Flutter port of the OpenGym web prototype: log gym sessions and other
activities, get the next session planned from your own log, and see a simple
summary. Everything is stored locally on the phone (shared_preferences). No
accounts, no sync.

The code was written without a compiler available, so run `flutter analyze`
first and fix anything it reports.

## Install on an iPhone

1. `cd mobile && flutter create . --platforms=ios --org io.devartel --project-name opengym`
   (generates `ios/`, keeps `lib/`)
2. `flutter pub get` then `flutter test`
3. `open ios/Runner.xcworkspace` -> Runner target -> Signing & Capabilities ->
   pick your team
4. Plug in the iPhone (Developer Mode on) -> `flutter run --release`

## Structure

- Domain: `lib/models.dart` (schema) and `lib/planner.dart` (planning rules, pure Dart).
- Data: `lib/data/` holds the `SessionRepository` interface plus shared_preferences and in-memory implementations.
- Store: `lib/store.dart` (`AppStore`) takes a repository and holds all mutations.
- Widgets: `lib/widgets/` are standalone. They import only Flutter, `theme.dart` and each other, and take plain values and callbacks.
- Screens: `lib/screens/` are thin. They read the store, map models to widget props and pass store methods as callbacks.
- Gallery: `lib/gallery/` is a dependency-free widget gallery (Storybook equivalent). Add a story with one entry in `lib/gallery/stories.dart`.

## Widget gallery

```
flutter run -t lib/gallery_main.dart
```
