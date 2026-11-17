# OpenGym API contract (v1)

> Note: this file still describes the old REST API. The live contract is the Convex functions in `backend/convex/functions` (ADR-012). Only the session, plan, prediction and start-request shapes below were updated for ADR-013 (activity first, focus is advice) and ADR-016 (start or log; the vocabulary comes from the log).

One backend, one core database, one user. The Flutter app (`mobile/`) and the
server (`backend/`) both build against this file. JSON everywhere, times are
epoch milliseconds, ids are client- or server-made strings.

## Principles

- **Facts vs proposals.** Facts (sessions, sets) are written only by the app or
  an import the user started. The AI never edits facts. Everything the AI makes
  (plans, dashboard layout, extracted goals/context, reviews) is a proposal
  with `source: "ai"` (or `"rules"` when the fallback produced it).
- **Strict schema.** Every AI output is parsed as JSON and validated (zod). On
  invalid output: one retry, then the plain-code fallback. The app never sees
  free-form AI data except chat text.
- **AI is never in the tap path.** Logging is local in the app. Endpoints that
  may call AI answer from stored proposals when one exists; generation happens
  after writes (session finished, goal changed, chat message, import).
- **No medical wording.** Prompts forbid diagnosis, rehab framing and clinical
  language. The coach talks about training only.
- **Auth.** `Authorization: Bearer <APP_TOKEN>` on every `/v1` route except
  `GET /v1/health`. 401 `{error}` otherwise. Errors: `{ "error": string }`.

## Schema

```ts
type Source = "app" | "user" | "ai" | "rules" | "import";

SetEntry   { reps: int 0..100, kg: number 0..500, max: boolean, failed?: boolean, at?: number }
           /* reps = completed reps. failed = one more rep was tried and not completed (the user's "6.5 reps") */
Exercise   { name: string 1..60, sets: SetEntry[] (<=12) }
Session    { id, kind: "gym" | "activity",
             type: string 1..40 /* the ACTIVITY name. kind gym = a session with sets: any name ("Gym" by default, "Home", ...);
                                   kind activity = time/distance: "Run", "Cycle", ... Names match by activityKey(name) = lower case,
                                   trimmed, inner whitespace collapsed; display uses the most recent spelling in the log. */,
             focus?: string 1..40 /* the flavour: "Upper", "Legs"; for a run "Easy", "Intervals". A label. */,
             startedAt, endedAt, exercises: Exercise[] (<=15, [] for activity),
             minutes?: int, distanceKm?: number, note?: string,
             source: "app" | "import", importId?: string }

PlanSet      { reps, kg, max }
PlanExercise { name, sets: PlanSet[], note?: string (<=120) }
Plan       { id, type: string /* the activity this plan is for, as the log spells it */, focus? /* the focus, when it has one */, createdAt, source: "ai" | "rules", rationale: string (<=200),
             exercises: PlanExercise[] }

Goal       { id, title 1..80, kind: "strength" | "consistency" | "work_around" | "custom",
             exercise?: string, targetKg?: number, sessionsPerWeek?: int,
             status: "active" | "done", source: "user" | "ai" | "import",
             threadId?: string, importId?: string, createdAt }
ContextItem{ id, text 1..300, topic: string 1..30, active: boolean,
             source: "user" | "ai" | "import", threadId?, importId?, createdAt }

Thread     { id, title 1..60, titleSource "auto"|"user", createdAt, updatedAt, summary: string, lastMessage?: string }
Message    { id, threadId, role: "user" | "assistant", text, fileIds: string[],
             sources: string[] /* what the coach also read, e.g. "Knee thread", "gym log", "goals" */,
             createdAt }
FileMeta   { id, name, mime, size, kind: "text" | "image" | "pdf" | "audio" | "other", createdAt }

Prediction { kind: "gym" | "activity", type: string /* an activity of the log; several set-based ones allowed; at most 2 items per activity, 6 in all */,
             focus?: string 1..40 /* advised flavour, when the log supports one */, reason: string (<=80) }
StartRequest { requestId, status: "pending" | "ready" | "failed",
             proposal?: { kind: "gym" | "activity", type: string 1..40, focus?: string (<=40), minutes?: int, reason?: string (<=80),
                          plan?: Plan /* required when kind is "gym", absent for "activity"; id is "start:<requestId>" */ } }

DashboardModule =
  | { type: "stat", label, value: string, highlighted: boolean }
  | { type: "goal_progress", goalId, title, current: string, target: string, fraction: number 0..1 | null }
  | { type: "trend", title, unit, points: { t: number, value: number }[] }
  | { type: "consistency", title, days: boolean[] /* oldest first */ }
  | { type: "recent_sessions", items: { title, subtitle, trailing }[] }
  | { type: "note", text }
Dashboard  { days: 7 | 30, source: "ai" | "rules", modules: DashboardModule[] (<=10) }

ImportJob  { id, status: "running" | "done" | "failed", total: int, processed: int,
             counts: { sessions, goals, context }, notes: string[], createdAt }
Review     { sessionId, source: "ai" | "rules", summary: string (<=400), changes: string[] (<=5) }
```

All numbers in dashboard modules are computed by code from facts. The AI only
chooses which modules, their order and their parameters (which exercise, which
goal).

## Endpoints

| Method | Path | Body | Returns |
|---|---|---|---|
| GET | `/v1/health` | – | `{ ok: true, provider, aiConfigured: boolean, version }` |
| GET | `/v1/sessions?since=<ms>` | – | `{ sessions: Session[] }` (endedAt > since, oldest first) |
| PUT | `/v1/sessions/:id` | Session | `{ session }` idempotent upsert; then (async) review, replan, dashboard refresh |
| DELETE | `/v1/sessions/:id` | – | `{ ok: true }` |
| GET | `/v1/sessions/:id/review` | – | `{ review: Review | null }` |
| GET | `/v1/start` | – | `{ predictions: Prediction[] }` most likely first |
| GET | `/v1/plans/next?focus=Upper` (Convex: `queries/plans:next { activity?: string (default "Gym"), focus?, type? (legacy name of focus) }`; no focus = the advised focus of that activity) | – | `{ plan: Plan, stored: boolean }` the stored plan, else the rules plan computed now: the user's own last session of that activity and focus, or an EMPTY plan (no starter template). Never calls the AI. |
| POST | Convex only: `commands/start:request { token, requestId, name?: 1..40, text?: 0..200 }` (at least one of `name`, `text`; a text-only request from an old client works as before) | – | the requestId. Idempotent by requestId. Stores `{requestId, text?, name?, status: "pending"}` and schedules `interpret_request`. Requests older than one day are removed. |
| GET | Convex only: `queries/start:request { token, requestId }` | – | `StartRequest` or `null` |
| GET | `/v1/dashboard?days=7` | – | `{ dashboard: Dashboard }` |
| GET | `/v1/goals` | – | `{ goals: Goal[] }` |
| POST | `/v1/goals` | `{ title, kind, exercise?, targetKg?, sessionsPerWeek? }` | `{ goal }` |
| PATCH | `/v1/goals/:id` | partial Goal (title, status, targets) | `{ goal }` |
| DELETE | `/v1/goals/:id` | – | `{ ok: true }` |
| GET | `/v1/context` | – | `{ items: ContextItem[] }` |
| POST | `/v1/context` | `{ text, topic }` | `{ item }` |
| PATCH | `/v1/context/:id` | `{ active?, text? }` | `{ item }` |
| DELETE | `/v1/context/:id` | – | `{ ok: true }` |
| GET | `/v1/threads` | – | `{ threads: Thread[] }` newest first |
| POST | `/v1/threads` | `{ title }` | `{ thread }` |
| DELETE | `/v1/threads/:id` | – | `{ ok: true }` |
| GET | `/v1/threads/:id/messages` | – | `{ messages: Message[] }` oldest first |
| POST | `/v1/threads/:id/messages` | `{ text, fileIds?: string[] }` | `{ userMessage, assistantMessage, extracted: { goals: Goal[], context: ContextItem[] } }` |
| POST | `/v1/files` | multipart, field `file` (<=20 MB) | `{ file: FileMeta }` |
| GET | `/v1/files/:id` | – | the file bytes |
| POST | `/v1/import` | multipart, field `files` repeated (text, json, md, csv, pdf, images) | `{ job: ImportJob }` returns at once, runs in background |
| POST | `/v1/import/structured` | JSON `{ sessions[≤2000], goals?, context?, note? }`, items as in the schema, `id` optional | `{ job: ImportJob }` already `done`; 400 names the bad item and nothing is stored |
| GET | `/v1/import/:id` | – | `{ job: ImportJob }` |
| GET | `/v1/import` | – | `{ jobs: ImportJob[] }` newest first |
| DELETE | `/v1/import/:id` | – | `{ ok: true }` removes every session/goal/context item with that importId |
| GET | `/v1/ai/functions` | – | `{ functions: { name, description, fallback: string }[] }` |

Changing goals, context, sessions or finishing an import invalidates stored
plans and the dashboard layout; they are regenerated in the background.

`POST /v1/import/structured` makes no AI call and queues no per-session review.

## AI jobs (each: prompt + zod output schema + fallback)

| Job | Output | Fallback (plain code) |
|---|---|---|
| `plan_session` | Plan for a session with sets for one activity (and focus) from log, goals, active context (equipment and preferences), limits | the user's last session of that activity and focus with its last sets; an EMPTY plan if there is none |
| `predict_activity` | Prediction[] (names checked against the log by activityKey; max 2 per activity, 6 in all) | the log's activities ranked by recent use; a session with sets gets the focus done longest ago, plus a second item when the log has a second focus; empty for an empty log |
| `interpret_request` | StartRequest proposal for a typed text: activity (a known name is reused by activityKey), focus, minutes, reason, plan | status `ready` with `{kind: "gym", type: <name as typed, else the text before the first comma>, plan: empty}`. With a `name`, the proposal `type` is always that name (the log's spelling when the key matches); the job gets `name` and `wish` (the text) as separate inputs |
| `build_dashboard` | ordered module specs | sessions, active days, top set of most-trained exercise, one goal_progress per active goal, recent_sessions |
| `chat` | reply text + sources | fixed "AI is not configured" reply; message still stored |
| `extract_from_chat` | new Goal[] / ContextItem[] from a user message | none extracted |
| `title_thread` | Thread.title (<=40 chars, no quotes, no trailing period), first message only, never over a user title | first words of the first message |
| `summarise_thread` | Thread.summary (<=400 chars) | last user message truncated |
| `review_session` | Review | set counts and top sets vs previous session of the same activity and focus |
| `import_data` | Session[] / Goal[] / ContextItem[] from a text chunk or an image | nothing imported; job note says AI is required |

Plan safety limits applied in code after validation: at most 12 exercises and
10 sets each; a planned weight may not exceed 1.25 × the heaviest logged
weight for that exercise (when history exists).

## Providers

`AI_PROVIDER=anthropic | openai | deepseek | mock`. One interface:
`complete({ system, messages, images?, json: boolean, maxTokens }) -> string`.
Model names come from env (`ANTHROPIC_MODEL`, `OPENAI_MODEL`, `DEEPSEEK_MODEL`).
Images are sent to Anthropic and OpenAI; DeepSeek has no image input, so image
imports and image attachments answer with a clear note instead.
`mock` returns deterministic canned JSON so the whole flow can be tested with
no key.
