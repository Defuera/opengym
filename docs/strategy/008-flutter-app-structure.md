# ADR-008: Flutter App Structure and In-App Widget Gallery

## Status

Accepted

## Date

2026-11-16

## Context

The owner asked for standalone widgets, SOLID design and Storybook-style tooling so designs are easy to rework. Widgetbook was not used because packages could not be fetched or compiled where the code was written. Source: DECISIONS.md.

## Decision

State and layers:

- `AppStore` holds the live session. One small store holds each other concern.
- Widgets in `lib/widgets` import only Flutter, `theme.dart` and each other.
- Screens are thin.
- Composition happens in `lib/app/compose.dart`.

Widget gallery:

- The gallery is an in-app page with no extra dependency.
- Run it with `flutter run -t lib/gallery_main.dart`.

Dependencies: `shared_preferences`, `http`, `file_picker`, `image_picker`.

## Consequences

- A widget can be developed and reviewed alone in the gallery.
- Swapping to Widgetbook later is reasonable (DECISIONS.md).
- Two files are over the target of about 250 lines: `store.dart` (331) and `fake_open_gym_api.dart` (308).
- The handover says the Flutter code had never been compiled when it was written. Run `flutter analyze` first.
