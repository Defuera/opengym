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
