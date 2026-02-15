# OpenGym MVP Plan

## Phase 0: UI + SQLite DB (Implemented)
- Next.js (App Router) + TypeScript + Tailwind + PWA shell
- SQLite with Prisma ORM and libSQL adapter
- Models: User, Session (with date, status), Exercise (name, muscle group), Set (reps, weight, order)
- Seeded database with default user and sample sessions (past completed + active session)
- Routes:
  - `/` home: start new session button + recent sessions list from DB
  - `/session/[id]`: phone-first in-session UI with exercise navigation and main exercise card, editable sets saved via API
  - `/session/[id]/summary`: static DB-based summary with totals, muscle groups, exercise breakdown
- API routes:
  - `POST /api/sessions`: create new session
  - `PATCH /api/sets/[id]`: update set reps/weight
  - `POST /api/sessions/[id]/complete`: mark session as completed
- No AI yet; all deterministic data from SQLite.

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
