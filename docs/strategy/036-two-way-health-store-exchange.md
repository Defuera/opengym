# ADR-036: Two-Way Exchange With the Phone's Health Store

## Status

Accepted. Supersedes three lines of [ADR-019](019-trackers-through-the-phone-health-store.md): "Read only", "Nothing goes to the server yet" and "It never asks to write".

## Date

2026-11-25

## Context

The owner asked how hard it would be to connect the Google Health app. Offered two directions (data in, or data in and out), he answered, in his words: "I want two way information exchange".

The route stays the one in ADR-019: the phone's health store (Health Connect on Android, Apple Health on iPhone), through the `health` plugin that is already in the app. It is not a cloud interface of a brand.

## Decision

**In: health store to Gym Days to coach.**

- Two new tables, `trackerDays` (one row per local date: sleep minutes and stage minutes when present, resting heart rate, steps, active energy) and `trackerWorkouts` (one row per store workout, keyed by the store's own id: type, start, end, minutes, distance, energy, average heart rate, source app name).
- One token-checked mutation, `commands/tracker:sync`, upserts a batch. It is idempotent by date and by workout id. It caps a call at 31 days and 100 workouts and checks every field range.
- These rows are tracker readings. They are never sessions, and no AI job writes them (ADR-002).
- The app sends the last 14 days when it comes to the foreground (at most once in 15 minutes) and when the person presses "Send now". It does this only when the switch "Send tracker data to my coach" is on. The switch starts off and its turning on runs the read permission request. Sync never blocks the screen, never shows an error for being offline, and keeps no queue: the next sync sends the window again.
- Own writes do not come back (below).

**What goes to the AI provider.** ADR-019 records that the owner agreed sleep and heart rate go with coach requests. This change sends more than that, so it is listed here: for the last 7 days one line per day (sleep hours, resting heart rate, steps, active kcal); for the last 14 days one line per tracker workout (date, time, type, minutes, distance, average heart rate). It goes to `coach_turn`, `build_session`, `plan_session` and `review_session`. Missing values are left out. Each of those four prompts has one sentence: this is tracker data from the phone, use it for recovery and load, a tracker workout is not a logged session, do not comment on it unless it matters. No wording rules (ADR-022). Not stated by the owner: that stage minutes and active energy also go. They are in the tables; only the lines above reach the prompt, and the stage minutes appear in the day line when present. Review this.

**Duplicate rule.** A tracker workout that overlaps a logged session in time (give or take 15 minutes) is the same workout. It is not listed as a workout. If it has an average heart rate or energy, those two numbers appear on a line "tracker saw ..." naming that session. Otherwise it is dropped.

**Out: Gym Days to health store.**

- When a session is finished in the app, one workout is written, only when the switch "Write my sessions to Health" is on (starts off; turning it on runs the write permission request).
- Activity type from the activity name (run, walk, cycling, swimming, hiking, rowing, yoga); a session with sets is strength training; anything else is "other". Title is activity and focus. Start, end and distance (when the session has one) are written.
- Once per session id, remembered on the phone. A continued session that is finished again is not written again. Editing or deleting a session later does not touch the store; the screen says so in one line.
- A failed write never blocks finishing the session. A session logged as one text has no real times and is not written.

**Own-writes filter.** The plugin has no metadata parameter on `writeWorkoutData`, so a marker cannot be set. Workouts are told apart by the source id the plugin returns for each point: the Android package name or the iOS bundle id, `io.devartel.opengym`. A workout with that id (or that id as a prefix) is dropped when reading, in the reading code and again before sending.

## What the plugin cannot write

Read in the plugin source, `health` 13.3.1 (`lib/src/health_plugin.dart`, `writeWorkoutData`): activity type, start, end, total energy (whole kcal), total distance (whole metres), a title (used by Health Connect only) and a recording method. It cannot write sets, reps, weights, exercises, notes, heart rate or a metadata marker. So the health store gets a workout with a time and a distance, not the gym log. The app writes no energy: a session has none.

Per platform (read in `HealthDataWriter.kt` and `HealthDataWriter.swift`): Android inserts an exercise session record, plus a distance record when a distance is given. iPhone saves one `HKWorkout`. The Android activity type map has no plain swimming, so the app writes pool swimming there.

## Not verified

- NOT VERIFIED: whether the Google Health app shows workouts that another app wrote to Health Connect.
- NOT VERIFIED: any behaviour on a real phone: the permission screens, the real source ids of Fitbit data, sleep stage data, whether a written workout appears in the store and in the Google Health app, and the filter on a real device. Tests use fakes behind the `TrackerSource` interface.
- Inferred, not verified: the iOS write passes energy and distance as whole numbers and Swift reads them as doubles; the app writes no energy and the distance is whole metres, so this should hold.
- Inferred: when two sources write active energy for one day, taking the larger source avoids counting twice. The plugin has no merge for it.
- Inferred: the server reads a tracker date as given by the phone and compares it with the server time zone (`APP_TIMEZONE`). A phone in another time zone may be off by a day at the edges.

## Consequences

- Health data is now stored on the server and goes to the AI provider. It is the owner's data and he asked for it; a second user would need a consent step first.
- Reading works only while the app is in the foreground (no background sync, as in ADR-019).
- iPhone does not say whether reading was refused. An empty result looks the same as no data.
- The HealthKit capability must be on the App ID for a signed device build. Writing needs `NSHealthUpdateUsageDescription` (added) in addition to the read text.

- Decided by the agent (Proposed): when the server holds no tracker data, the coach chat context (`assembleCoachContext`, used by `coach_turn`) carries one plain fact (`NO_TRACKER_DATA_FACT`): what the app can receive, how to turn it on (Settings > Trackers), and that live heart rate never arrives. The present path, the session builder, plan and review are unchanged.
