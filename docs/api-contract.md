# OpenGym API contract (v1)

> Note: this file still describes the old REST API. The live contract is the Convex functions in `backend/convex/functions` (ADR-012). Only the session, plan and start-request shapes below were updated for ADR-013 (activity first, focus is advice) and ADR-016 (start or log; the vocabulary comes from the log).

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
TimeEntry  { minutes: number >0..600, distanceKm?: number >=0, note?: string (<=200), at?: number }
           /* one entry of a time exercise (a bike, a hold, a treadmill). No reps, no kg. Usually one entry; more are allowed (intervals). */
Exercise   = { name: string 1..60, measure?: "sets", sets: SetEntry[] (<=12) }        /* sets and reps; `measure` is absent in all stored data = "sets" */
           | { name: string 1..60, measure: "time", sets: TimeEntry[] (<=12) }       /* time: the work is held as `sets` entries of minutes (and distance) */
           /* The two shapes are not mixed: a "sets" exercise needs reps/kg on every entry and takes no minutes; a "time" exercise needs minutes and takes no reps/kg.
              Old rows have no `measure` and stay valid; nothing was rewritten. The Convex validator is a union of the two exercise shapes. */
Session    { id, kind: "gym" | "activity",
             type: string 1..40 /* the ACTIVITY name. kind gym = a session with sets: any name ("Gym" by default, "Home", ...);
                                   kind activity = time/distance: "Run", "Cycle", ... Names match by activityKey(name) = lower case,
                                   trimmed, inner whitespace collapsed; display uses the most recent spelling in the log. */,
             focus?: string 1..40 /* the flavour: "Upper", "Legs"; for a run "Easy", "Intervals". A label. */,
             startedAt, endedAt, exercises: Exercise[] (<=15, [] for activity),
             minutes?: int, distanceKm?: number, note?: string,
             source: "app" | "import", importId?: string,
             placeId?: string 1..100 /* where the session happened (ADR-021). Stored as given, an unknown id too. A save without it keeps the stored one; only commands/sessions:setPlace clears it. */,
             parse?: "pending" | "done" | "failed" /* only on a session logged as one text (ADR-018); written by the server: pending until parse_log has read the note. A user save never writes it. */ }

PlanSet      { reps, kg, max }
PlanTimeSet  { minutes: number >0..600, distanceKm?: number >=0 }
PlanExercise = { name, measure?: "sets", sets: PlanSet[], note?: string (<=120) }
             | { name, measure: "time", sets: PlanTimeSet[], note?: string (<=120) }
Plan       { id, type: string /* the activity this plan is for, as the log spells it */, focus? /* the focus, when it has one */, createdAt, source: "ai" | "rules", rationale: string (<=200),
             exercises: PlanExercise[] }

Goal       { id, title 1..120, kind: "strength" | "consistency" | "custom",
             exercise?: string, targetKg?: number, sessionsPerWeek?: int,
             status: "active" | "done", source: "user" | "ai" | "import",
             threadId?: string, importId?: string, createdAt }
ContextItem{ id, text 1..300, topic: string 1..30, active: boolean,
             source: "user" | "ai" | "import", threadId?, importId?, createdAt }

Thread     { id, title 1..60, titleSource "auto"|"user", createdAt, updatedAt, summary: string, lastMessage?: string,
             placeId?: string /* the conversation is about this place (ADR-021) */ }
Place      { placeId: string 1..100 (client- or server-made), name: string 1..30 (unique by key: trim, lower case, inner spaces collapsed),
             text: string 0..1500 /* the equipment in free text; "" = not known yet */, updatedAt }
           /* Tables: `places` (+ createdAt, index by_placeId) and `placeChanges`, a trace the app never reads:
              { placeId, at, source: "feedback" | "note" | "chat" | "user" | "seed", quote (the user's sentence, <=300), before, after }. */
Message    { id, threadId, role: "user" | "assistant", text, fileIds: string[],
             sources: string[] /* what the coach also read, e.g. "Knee thread", "gym log", "goals" */,
             createdAt }
FileMeta   { id, name, mime, size, kind: "text" | "image" | "pdf" | "audio" | "other", createdAt }

Prediction   /* removed from the contract: the AI job `predict_activity` and `queries/start:predictions` no longer exist. The Start tab lists the activities of the log (plain code). The `predictions` table stays in the schema only so old rows validate. */
StartRequest { requestId, status: "pending" | "ready" | "failed",
             proposal?: { kind: "gym" | "activity", type: string 1..40, focus?: string (<=40), minutes?: int, reason?: string (<=80),
                          plan?: Plan /* required when kind is "gym", absent for "activity"; id is "start:<requestId>" */,
                          place?: { placeId, name } /* where the session is for (ADR-021); absent when no place is known */ } }

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
| GET | `/v1/plans/next?focus=Upper` (Convex: `queries/plans:next { activity?: string (default "Gym"), focus?, type? (legacy name of focus) }`; no focus = the advised focus of that activity) | – | `{ plan: Plan, stored: boolean }` the stored plan, else the rules plan computed now: the user's own last session of that activity and focus, or an EMPTY plan (no starter template). Never calls the AI. |
| POST | Convex only: `commands/start:request { token, requestId, name?: 1..40, text?: 0..2000, feedback?: 1..1000, previousRequestId?: string }` (at least one of `name`, `text`, unless the two feedback arguments are given. `feedback` and `previousRequestId` come together or not at all: the person read the proposal of the request `previousRequestId` and asks for a change, e.g. "no water bottles, I have dumbbells". The new request copies `name` and `text` from the previous row (an error when that row is gone) and ignores any `name` or `text` sent with it; it stores `feedback`, an array of strings (the feedback of the previous row, then this one, at most 5, oldest dropped), and `previousPlan`, a compact copy of the previous proposal's plan (exercise names with sets, no notes). `build_session` gets them as `previousPlan` and `feedbackFromThePerson`. When the AI fails for such a request the status is `failed` and there is no rules plan. Old app builds do not send them. The Start tab sends the activity the user chose as `name` and the optional note as `text`; "Other" sends only `text`, what the user wants to do, and the coach names the activity. In both cases the coach decides the focus and the plan. The earlier `mode: "today"`, `hintType` and `hintFocus` arguments were removed) | – | the requestId. Idempotent by requestId. Stores `{requestId, text?, name?, status: "pending"}` and schedules `build_session`. Requests older than one day are removed. Old rows may still hold `mode`, `hintType`, `hintFocus`; the schema keeps them optional and nothing reads them. |
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
| `build_session` | StartRequest proposal for a start request: a session with exercises (`kind: "gym"`; time or distance work is a time exercise): focus, minutes, reason, plan. The job gets the full picture of the user (`coachPicture`), `activity` and `noteForToday`; for a text-only request `activity` is `null` and `request` holds the text, and the coach names the activity (one to three words, a name from the log when it means the same). On a rebuild (a feedback request) it also gets `previousPlan` and `feedbackFromThePerson` (an array of strings). It also gets `placesTheCoachKnows: [{name, equipment, lastUsedForThisActivity}]` (every place; `equipment` is the place text, `""` when unknown; the flag marks the place of the newest session of the chosen activity) and may return `place` (max 30): a name from that list, or a new short name when the request clearly means a place the coach does not know (ADR-021). | status `ready` with `{kind: "gym", type: <the name, else the text before the first comma (first letter upper case, max 40; a known spelling when the log has one)>, plan: the user's last session of that activity, else empty}`. With a `name`, the proposal `type` is always that name (the log's spelling when the key matches). Without a name it is the coach's name, trimmed to 40. |
| `learn_place` | Keeps the equipment note of ONE place up to date from one sentence the user said (ADR-021, the second exception to ADR-002; only places). Input: `{place: {name, equipment}, otherPlaces: [name], sentence}`. Output: `{changed: boolean, equipment: string (<=1500)}`. Never blocks a reply: scheduled (`jobs/places:learn`) (1) after a start request with feedback is saved (the sentence is the newest feedback; source `feedback`), (2) after a start request with a note or text and no feedback is saved (source `note`), both for the place of the proposal, and (3) after a user message in a thread that has `placeId` (source `chat`). Code writes `places.text` only when `changed` is true, the text differs and the stored text is still the one the job read (a newer edit wins), and logs a `placeChanges` row with the source and the quote (the sentence, cut to 300) | No change. |
| `build_dashboard` | ordered module specs | sessions, active days, top set of most-trained exercise, one goal_progress per active goal, recent_sessions |
| `chat` | reply text + sources | fixed "AI is not configured" reply; message still stored |
| `extract_from_chat` | new Goal[] / ContextItem[] from a user message | none extracted |
| `parse_log` | Structure of one text-logged session (ADR-018). Input: `{activity, text, today (date and weekday), exercisesTheUserKnows: [{name, lastSets, measure?}]}` (from `coachPicture`). Output: `{minutes?, distanceKm?, focus?, date? (YYYY-MM-DD), exercises?: [{name, measure?: "time", sets?: [{reps, kg} \| {minutes, distanceKm?}]}]}`. Scheduled by `commands/sessions:logText`. Patches only `minutes`, `distanceKm`, `focus`, the day of `startedAt/endedAt` (time of day kept; a future day or one more than a year back is ignored) and `exercises` (then `kind` becomes `gym`), sets `parse` to `done`, then schedules the facts-changed rebuild and the review like `save`. An exercise named without sets gets the sets of its last logging in plain code; one that is not in the log and has no sets is left out. Never changes `note`, `type` or `source`. Dropped when the session is gone, `parse` is no longer `pending` or the stored note is not the text read (the user edited it). Derived structure of the user's own text, not a new fact (ADR-002, ADR-018) | Minutes (`45 min`, `1h`, `1h30`, `1:10`) and km (`8 km`) by regex; `parse` is `failed` only when nothing was read |
| `parse_goal` | Structure of the user's own goal text: `{kind, exercise? (a name of the log), targetKg?, sessionsPerWeek?}`. Scheduled by `commands/goals:create`, and by `goals:update` when the title changes (the old structure is cleared first). Patches only those fields, and only while the goal exists and its title is still the text read. Never changes title or status. Derived structure, not a new fact (ADR-002) | kind stays `custom`; a number before `kg` and a number before "times/sessions a week" are read when present |
| `title_thread` | Thread.title (<=40 chars, no quotes, no trailing period), first message only, never over a user title | first words of the first message |
| `summarise_thread` | Thread.summary (<=400 chars) | last user message truncated |
| `review_session` | Review | set counts and top sets vs previous session of the same activity and focus |
| `import_data` | Session[] / Goal[] / ContextItem[] from a text chunk or an image | nothing imported; job note says AI is required |

Plan safety limits applied in code after validation: at most 12 exercises and
10 sets each; a planned weight may not exceed 1.25 × the heaviest logged
weight for that exercise (when history exists). A time exercise has no weight,
so the weight cap does not apply to it.

Time exercises (a bike, a plank hold, a treadmill) inside a session with sets:
- Time fitting of a start proposal with `minutes`: the budget is max(4, minutes / 2) sets, that is about 2 minutes per set.
  A normal set costs 2 minutes; a time entry costs its own minutes (the last entry that does not fit is shortened).
- The rules plan copies the last time entry of an exercise. An exercise that was never logged with entries stays empty.
- Load levels: a time exercise loads its muscles by minutes, about one set per 4 minutes. The muscle keywords also know bike, cycling, treadmill, running and rowing machine.
- Records such as best weight, the top set, the "Sets" stat and the most-trained exercise ignore time entries.
- Prompts print a time entry as "25 min" or "25 min, 10.9 km". `coachPicture` gives `lastSets` the same way and adds `measure: "time"` for such an exercise.
- The AI writes a time exercise as `{"name", "measure": "time", "sets": [{"minutes"}], "note"?}` next to the normal form (jobs `plan_session`, `build_session`).
- The app's add-exercise sheet lists the exercises of the user's own log (most recently used first, the log's spelling) and nothing else.
  A new name asks "Sets and reps" or "Time"; a name from the log keeps the measure it had last time.

## Providers

`AI_PROVIDER=anthropic | openai | deepseek | mock`. One interface:
`complete({ system, messages, images?, json: boolean, maxTokens }) -> string`.
Model names come from env (`ANTHROPIC_MODEL`, `OPENAI_MODEL`, `DEEPSEEK_MODEL`).
Images are sent to Anthropic and OpenAI; DeepSeek has no image input, so image
imports and image attachments answer with a clear note instead.
`mock` returns deterministic canned JSON so the whole flow can be tested with
no key.

## Log entries (Convex backend, ADR-017)

A log entry is a free note with a time and any number of attached files. It has no type. It is a fact: only the app writes it. The coach reads it; the AI never writes or changes it.

`Entry = { entryId: string (client-made, 1..100), text: string (0..2000), fileIds: string[] (0..10), at: number (ms, the time the entry is about), createdAt: number (ms) }`. Rule: `text.trim()` is not empty, or `fileIds` is not empty. Table `entries`, indexes `by_entryId` and `by_at`.

| Function | Args | Returns |
|---|---|---|
| mutation `commands/entries:save` | `{ token, entry: Entry }` | the entryId. Idempotent upsert by entryId. Every fileId must be a registered file (`commands/files:register`). A file that an update drops is deleted (row and blob). A bad entry is rejected with a `ConvexError` and nothing is stored |
| mutation `commands/entries:remove` | `{ token, entryId }` | `true` when this call marked the entry, `false` if it is unknown or already marked. It only marks the row (`deletedAt = now`); the entry leaves every read at once, and its files stay until the purge erases it 72 hours later (ADR-020) |
| query `queries/entries:recent` | `{ token, limit?: number }` | newest first by `at`. Default 50, at most 200. Each item: `{ entryId, text, at, createdAt, files: { fileId, name, mime, size, kind, createdAt, url: string \| null }[] }`. A missing file is left out |

Upload uses `commands/files:generateUploadUrl` and `commands/files:register`, as for chat.

**Session recap.**

| Function | Args | Returns |
|---|---|---|
| query `queries/sessions:load` | `{ token, sessionId }` | What one session loaded, for the body figure on its recap: `Record<muscleKey, 0 \| 1 \| 2 \| 3>` with every muscle key present, or `null` when the session is unknown. It uses the exercise-to-muscle table and the same level rule as the "About me" load (the busiest muscle of this session is the top: share >= 0.6 is 3, >= 0.25 is 2, above 0 is 1; a time exercise counts one set per 4 minutes). The code is shared (`model/rules/load.ts`, `loadForSession`). Additive: no stored row changes |

**Log by text (ADR-018).** `commands/sessions:logText { token, sessionId, type (1..40), text (1..1000, not blank), at: number }` is an idempotent insert by `sessionId`: the same id again changes nothing and schedules nothing. It stores a session as a fact: `kind: "activity"`, `type`, `startedAt = endedAt = at`, `exercises: []`, `note: text` (word for word), `source: "app"`, `parse: "pending"`, and schedules `parse_log`. The app's session subscriptions (`queries/sessions:recent`, `since`) return `parse`, so the recap updates when the structure arrives. `commands/sessions:save` accepts a session that carries `parse` but never stores it: a resend of an unchanged session keeps the stored `parse`; a real edit clears it, so a late `parse_log` result is dropped.

A past session is corrected with the same `commands/sessions:save` (an idempotent upsert by `sessionId`): the app sends the full session again with its `sessionId`, `kind`, `source` and `importId` unchanged. A changed session schedules a new review. 

**Delete marks, then purges (ADR-020).** `commands/sessions:remove { token, sessionId }` and `commands/entries:remove { token, entryId }` only mark the row: they set the optional `deletedAt` (epoch ms, the time of the first call; a second call keeps it) and return `true` when this call marked it, `false` when the row is unknown or already marked. Nothing else goes at that moment, not the review of a session and not the files of a note. A session's mark also asks for a rebuild of the read models. A marked row is invisible to every read: the queries, the jobs, the coach picture, the chat context, dashboards, plans, reviews and load levels. A `commands/sessions:save`, `logText` or `commands/entries:save` for a marked id changes nothing and returns the id, so a late resend from an offline phone does not bring it back. A pending `parse_log` or review result for a marked session is dropped. An hourly cron (`crons.ts`, `jobs/purge:run`) erases every row marked more than 72 hours ago (`DELETE_AFTER_MS`), in batches of 50: a session with its review, a note with its file rows and blobs. The operator can undo a delete within 72 hours with the internal functions `commands/sessions:restoreSession { sessionId }` and `commands/entries:restoreEntry { entryId }` (run with `npx convex run`; there is no app screen for it). The app asks for confirmation before it removes a session or a note, and says that the erasing follows after 72 hours.

Coach: `coachPicture` (the `build_session` input) has a field `logEntriesFromTheUser`: the entries of the last 7 days, oldest first, at most 20, each `{ date, time, text, attachments: number }`. The chat context lists the same entries. The image files of entries of the last 24 hours (at most 4, newest first) go with the `build_session` request and the chat request when the provider takes images; DeepSeek has no image input, so no image is sent there.

## Places (Convex backend, ADR-021)

A place is a fact: where the user trains and what is there, in free text (`Place` in the schema). The user never has to make one. The coach picks today's place for a proposal, and a background job learns the equipment text from the user's own words. All fields are optional and old app builds keep working.

| Function | Args | Returns |
|---|---|---|
| query `queries/places:list` | `{ token }` | `[{ placeId, name, text, updatedAt }]`, sorted by name |
| mutation `commands/places:save` | `{ token, placeId (1..100), name (1..30 after trim), text? (0..1500) }` | the placeId. Idempotent upsert by placeId. `text` left out keeps the stored text. Rejects a name whose key (trim, lower case, inner spaces collapsed) belongs to another placeId. A change of the text logs a `placeChanges` row with source `user`. |
| mutation `commands/sessions:setPlace` | `{ token, sessionId, placeId: string (1..100) \| null }` | `true`; `false` when the session is unknown or marked as deleted. Sets or clears the place of that one session; nothing else on the row changes and no rebuild or review is scheduled. The id is stored as given. |
| mutation `commands/sessions:save` | the session may carry `placeId` | as before. A save WITHOUT `placeId` (an old app) never erases the stored one. |
| mutation `commands/threads:create` | `{ token, threadId, title?, placeId? }` | as before. `placeId` (1..100) says the conversation is about that place. A resend changes nothing. `queries/threads:list` returns `placeId` when set. |
| query `queries/sessions:recent`, `queries/sessions:since` | as before | each session carries `placeId` when set |
| query `queries/start:request` | as before | `proposal.place: { placeId, name }` when a place is known |

How the place of a proposal is set (`jobs/startRequest:save`, plain code): the name the coach gave is matched to a place by its key; a new name makes a place with an empty text; when the coach gave none, or on the rules fallback, the place of the newest live session of the same activity is used (none when that session has no place, or its place is not stored). `build_session` input and output are in the AI jobs table.

Chat: when the thread has `placeId` and the place exists, the coach input of `chat` names the place and its equipment text and says the conversation is about it. A place text goes to the AI provider; a record (ADR-015) never does. `commands/messages:send` schedules `learn_place` for a message in such a thread.

Seed (once, by the operator, idempotent): `internal.jobs.places:seed {}`. It makes the place "Gym" with the text of the active context item(s) whose topic is "equipment" and sets those items inactive (so the equipment is not sent twice), logs a `placeChanges` row with source `seed`, makes the place "Home" with an empty text, and gives every live session with no place a place: activity "Gym" (an old flavour name counts as Gym) to Gym, "Home" or a name that starts with the word home to Home, other sessions stay as they are; sessions marked as deleted are not touched. At most 2000 sessions per run; `remaining` in the result tells if another run is needed. Returns `{ gymCreated, homeCreated, equipmentMoved, sessionsGym, sessionsHome, remaining }`. A second run changes nothing.

## Voice message in the chat (Convex backend)

The user records speech; the server turns it into text; the message is then a normal text message and the coach answers as usual. All changes are additive; old app builds are not affected.

| Item | Contract |
|---|---|
| Upload | The existing flow: `commands/files:generateUploadUrl`, then `commands/files:register`. A file with mime `audio/*` (or an m4a, mp3, wav, aac, ogg, opus name) gets kind `"audio"`. The app records AAC in `.m4a` (`audio/mp4`), max 180 s. |
| mutation `commands/messages:sendVoice` | `{ token, threadId, messageId (1..100), fileId }` returns the messageId. Idempotent by messageId (a second call changes nothing). Rejects an unknown thread, an unknown file, a file that is not kind `audio`, and a file over 10 MB, with a `ConvexError`. Inserts a user message `{ text: "", fileIds: [fileId], voice: "pending" }`, sets the thread to `thinking` with `pending + 1`, and schedules `jobs/voice:transcribe`. A resend of the messageId through `messages:send` never starts a coach run for a voice message that is not `done`. |
| action `jobs/voice:transcribe` (internal) | Reads the blob and calls the provider's `transcribe`. Success with a non-empty text: stores the trimmed text (max 8000 characters, like a typed message) and `voice: "done"`, then schedules the same work as `messages:send` (`jobs/chat:reply`, and `jobs/places:learn` in a place thread). The unnamed thread gets its code title from the transcript. The `pending` count is not raised again. An empty transcript, a provider error, a provider without `transcribe`, or a missing blob: `voice: "failed"`, `pending - 1`, status `idle` (`thinking` while other replies run), no coach reply. A run for a message that is no longer `pending` does nothing, so the reply is scheduled once. The log holds only a short reduced text (`HTTP 401`, `timed out`), never a provider message. |
| mutation `commands/messages:retryVoice` | `{ token, messageId }` returns `true` and does for a message with `voice: "failed"`: sets `voice: "pending"`, thread `thinking` with `pending + 1`, schedules the transcription again. Returns `false` for any other message or an unknown id. |
| `messages.voice` | Optional `"pending" \| "done" \| "failed"`. `queries/messages:list` returns it when set. Absent on a typed message and on an assistant message. |
| Coach input | `jobs/chat:input` returns nothing for a message that is `pending` or `failed`. A voice message without a transcript is left out of the history of other replies and of the thread summary. A file of kind `audio` is never a coach file: not as text, not as an image, not in `sources`. Only the transcript (the message text) reaches the model. |
| Provider | Optional `transcribe(bytes, mime, filename): Promise<string>`. OpenAI: `POST {base}/v1/audio/transcriptions`, multipart form with `model` and `file`, answer `{ text }`, timeout 60 s. The model is the env `OPENAI_TRANSCRIBE_MODEL`, default `gpt-4o-transcribe`. Anthropic and DeepSeek have none. The mock returns a fixed text (a file named `silence...` gives an empty one). |

## Coach model (Convex backend)

The owner picks the coach model in the app's Settings. The choice lives in one
`settings` row: `aiModel?` (the override) and a cached model list
`modelList { models: string[], fetchedAt }` with `modelListError?` (a short
text without secrets). No key is ever stored or returned. The provider and its
key still come from the environment (`AI_PROVIDER`, `*_API_KEY`); the model
from Settings wins over `*_MODEL`. Every AI job reads the override at the start
of a run.

| Function | Args | Returns |
|---|---|---|
| query `queries/settings:ai` | `{ token }` | `{ provider: string, defaultModel: string \| null, model: string \| null, override: string \| null, models: string[], fetchedAt: number \| null, error: string \| null }`. `model` is the override, else the default. `error` is the last list refresh error |
| mutation `commands/settings:setAiModel` | `{ token, model: string \| null }` | nothing. `null` goes back to the default. A model id is 1..100 characters of `A-Za-z0-9._:-`. An id that is not in the list is allowed (the list can be stale). Writing the same value again changes nothing |
| mutation `commands/settings:refreshModels` | `{ token }` | nothing. Schedules a background action that asks the current provider for its models (`GET {base}/models` for OpenAI and DeepSeek, `GET {base}/v1/models` for Anthropic), keeps text and chat models (drops embedding, audio, tts, whisper, image, moderation and realtime ids), sorts them and stores them with `fetchedAt`. On an error the old list stays and `error` holds a short text. `mock` and `none` give an empty list |

If the provider refuses the model (HTTP 400 or 404), the job uses its plain
code fallback, as for any provider error. A wrong model name never breaks the
app.
