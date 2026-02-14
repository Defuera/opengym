# OpenGym MVP Plan

## Phase 0: Scaffold + Local Logging
- Next.js (App Router) + TypeScript + Tailwind + PWA shell
- SQLite with a light ORM or direct access (Prisma planned but can be wired later due to env limits)
- Base models (conceptually): User, Session, Exercise, Set, ExternalActivity (stub)
- Routes:
  - `/` home: start new session, list recent sessions
  - `/session/new`: stub session proposal (hardcoded exercises)
  - `/session/[id]`: in-session UI skeleton (exercise list + main card)
  - `/session/[id]/summary`: static placeholder summary
- No real AI yet; all deterministic placeholders.

## Phase 1: Rule-Based Session Proposer
- Simple logic based on recent sessions + external activities:
  - Alternate upper/lower or push/pull/legs based on last session.
  - Adjust total volume if recent load was high.
- Implement editable pre-session plan on `/session/new`.
- Persist completed sets with actual reps/weights.

## Phase 2: OpenGym Coach Agent
- Introduce AI layer with access to DB via API:
  - Natural language changes to active session (swap exercise, lower volume, etc.).
  - End-of-session AI summary on `/session/[id]/summary`.
- Wire up at least one provider (e.g. OpenAI) via server-side route.

## Phase 3+: Analytics, Stats, and Hosted DB
- Migrate from local SQLite to hosted DB (e.g. Supabase/Postgres).
- Add statistics views:
  - Volume over time per muscle group
  - PR tracking per exercise
  - Session history and trends
- Advanced features:
  - Fatigue management heuristics
  - Run integration (sync with external trackers, if desired)
