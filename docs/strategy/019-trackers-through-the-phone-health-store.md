# ADR-019: Trackers Through the Phone's Health Store

## Status

Proposed

Note: the owner chose this direction in a message. He has not confirmed this written decision.

Superseded in part by [ADR-036](036-two-way-health-store-exchange.md): the lines "Read only", "Nothing goes to the server yet" and "It never asks to write" no longer hold. The rest stands.

## Date

2026-11-18

## Context

The owner wants tracker data (workouts, sleep, heart rate, steps) in the app. His tracker is a Fitbit. Other users may have another brand. The phone already collects tracker data in one store: Apple Health on iPhone, Health Connect on Android. Fitbit writes into those stores.

## Decision

- The app reads tracker data from the phone's health store, not from a brand's interface. One `TrackerSource` interface has two doors: Apple Health (HealthKit) and Health Connect. Both go through the `health` plugin (`lib/data/tracker_source.dart`).
- Reasons: one integration covers every brand; no account linking on the server; a brand's interface covers one brand only.
- Read only. The app asks for read permission for workouts, sleep, heart rate, resting heart rate, steps, active energy and distance. It never asks to write.
- Sync happens when the user opens the screen or asks for it. There is no background sync.
- The first step is a check: Settings, Trackers shows what arrives for the last 7 days. Nothing goes to the server yet.
- The owner agreed that sleep and heart rate will go to the AI provider with coach requests. That is a later step and needs its own change to the contract and to ADR-015.
- No medical wording (ADR-010): the screen says "sleep", "heart rate", "steps".

## Reported, not verified by us

- Google turned off the old Fitbit developer interface in November 2026.
- The Google Health app passes Fitbit data to Apple Health since August 2026.

These come from the owner's research. We have not checked them. The decision does not depend on them: it holds for any brand that writes to the phone's store.

## Consequences

- iPhone never tells the app whether read access was denied. An empty result looks the same as no data. The screen says so.
- Android needs Health Connect installed (built in from Android 14).
- Data quality depends on what the tracker's own app writes to the store.
- Open: how a day of sleep and heart rate is summed up for the AI, and how two sources that write the same workout are merged.
