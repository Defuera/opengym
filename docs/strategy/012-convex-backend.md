# ADR-012: Hosted Convex Backend With Separate Commands and Read Models

## Status

Accepted

The owner chose this on 2026-11-17: Convex for live data updates, the hosted Convex cloud (not self-hosted), a model with commands and queries kept separate, and `dartvex` as the Flutter client. This record replaces the hosting part of [ADR-006](006-standalone-backend.md) and all of [ADR-009](009-cloud-run-hosting.md). The port is in progress; `backend/api` on Cloud Run stays until the app runs on Convex.

## Date

2026-11-17

## Context

The first backend was a standalone TypeScript service on Cloud Run with a SQLite file on a Cloud Storage volume. Observed on 2026-11-17, after an import of 68 sessions:

- The storage volume answered writes with rate-limit errors (HTTP 429) and write-order errors on the SQLite journal file. The data did land, but the store is fragile.
- Cloud Run paused the instance between requests, so the in-process queue that builds plans and the dashboard stalled.
- The app only gets new data when it asks. The owner wants live updates.

## Decision

- **Store and functions:** hosted Convex, project `gym-days` in the owner's personal team. Code lives in `backend/convex/`, functions in `backend/convex/functions/`.
- **Commands and queries are separate.**
  - Commands (`functions/commands/`) are Convex mutations. Only commands write facts: sessions, goals, context items, chat messages, imports.
  - Queries (`functions/queries/`) are Convex queries. The app subscribes to them and gets every change pushed.
  - Read models (plans, dashboard, predictions, reviews) live in their own tables. Background jobs build them after facts change. The app never waits for a job; it reads the stored read model.
  - Jobs (`functions/jobs/`) are internal Convex actions started by the Convex scheduler. They hold the AI pipeline from [ADR-004](004-ai-job-pipeline-and-plan-limits.md). The scheduler replaces the in-process queue.
- **Earlier rules stay:** the AI never writes facts ([ADR-002](002-facts-vs-ai-proposals.md)); logging on the phone is local and works offline ([ADR-003](003-ai-not-in-tap-path.md)); every AI job keeps prompt, provider, JSON, validation, one retry, code fallback ([ADR-004](004-ai-job-pipeline-and-plan-limits.md)).
- **Idempotent writes:** each fact carries an id made by the app, so the app's outbox can resend a write safely.
- **Model input is bounded:** a job sends only recent sessions to the model. Code that computes numbers or applies limits reads the full history.
- **Flutter client:** the community package `dartvex`, pinned to an exact version, behind the `ConvexClient` interface in `apps/mobile/lib/data/` so it can be replaced. Convex has no official Flutter client.
- **Access:** interim single-user gate. Every public function takes the shared app token and checks it against a deployment variable. Real user accounts are required before a second person uses the app.

## Consequences

- Verified by a trial on 2026-11-17 (`apps/mobile/tool/convex_trial.dart` against the dev deployment): subscribe, save, live update and error paths work. The live update arrived about 60 to 70 ms after the mutation call, with no second query. The package builds for the iOS simulator with Flutter 3.44.
- Not verified: reconnect after a network drop, behaviour when iOS suspends the app, and that `dartvex` keeps up with Convex protocol changes. The package is young, pre-1.0 and has one maintainer.
- `dartvex` keeps unsent writes in memory only. The app's own outbox must keep them across restarts.
- Cloud Run, the storage bucket and `infra/deploy-cloud-run.sh` go away when the port is done.
- The repository interfaces in `backend/api` do not carry over as they are; Convex functions read and write through `ctx.db`. The schemas, rules and AI job code are plain TypeScript and move over.
