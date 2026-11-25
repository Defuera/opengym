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
| POST | Convex only: `commands/start:request { token, requestId, name?: 1..40, text?: 0..2000, feedback?: 1..1000, previousRequestId?: string, previousPlan?: PreviousPlan }` (at least one of `name`, `text`, unless the feedback arguments are given. `feedback` comes with exactly one of `previousRequestId` and `previousPlan`, and neither goes without `feedback`. `previousPlan` (1..30 exercises, the compact plan shape: exercise names with sets, no notes) is for a session that did not come from a start request, for example a program session: the row gets `name` (required, 1..40), `feedback: [feedback]` and `previousPlan` as sent, and the job works as for any rebuild (a failed AI means `failed`); a `text` sent with this form is kept as the note for today, so the note of a first request is not lost when the app's own plan replaced a late answer. The `previousRequestId` form: the person read the proposal of the request `previousRequestId` and asks for a change, e.g. "no water bottles, I have dumbbells". The new request copies `name` and `text` from the previous row (an error when that row is gone) and ignores any `name` or `text` sent with it; it stores `feedback`, an array of strings (the feedback of the previous row, then this one, at most 5, oldest dropped), and `previousPlan`, a compact copy of the previous proposal's plan (exercise names with sets, no notes). `build_session` gets them as `previousPlan` and `feedbackFromThePerson`. When the AI fails for such a request the status is `failed` and there is no rules plan. Old app builds do not send them. The Start tab sends the activity the user chose as `name` and the optional note as `text`; "Other" sends only `text`, what the user wants to do, and the coach names the activity. In both cases the coach decides the focus and the plan. The earlier `mode: "today"`, `hintType` and `hintFocus` arguments were removed) | – | the requestId. Idempotent by requestId. Stores `{requestId, text?, name?, status: "pending"}` and schedules `build_session`. Requests older than one day are removed. The job has 35 s; the app waits 40 s, then opens its own plan with a notice, and offers an answer that comes later until the first set is done. Old rows may still hold `mode`, `hintType`, `hintFocus`; the schema keeps them optional and nothing reads them. |
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
| `build_session` | StartRequest proposal for a start request: a session with exercises (`kind: "gym"`; time or distance work is a time exercise): focus, minutes, reason, plan. The job gets the full picture of the user (`coachPicture`), `activity` and `noteForToday`; for a text-only request `activity` is `null` and `request` holds the text, and the coach names the activity (one to three words, a name from the log when it means the same). On a rebuild (a feedback request) it also gets `previousPlan` and `feedbackFromThePerson` (an array of strings). It also gets `placesTheCoachKnows: [{name, equipment, lastUsedForThisActivity}]` (every place; `equipment` is the place text, `""` when unknown; the flag marks the place of the newest session of the chosen activity) and may return `place` (max 30): a name from that list, or a new short name when the request clearly means a place the coach does not know (ADR-021). | status `ready` with `{kind: "gym", type: <the name, else the text before the first comma (first letter upper case, max 40; a known spelling when the log has one)>, plan: the user's last session of that activity, else empty}`. With a `name`, the proposal `type` is always that name (the log's spelling when the key matches). Without a name it is the coach's name, trimmed to 40. The job also gets `fociTheUserUses`: the focus names the log holds per activity with sets, with how often each was logged. The coach reuses one of these names and gives a new focus only when none fits. Code keeps the log's spelling of a focus the log has. |
| `build_program` | A training program (`ProgramValue` plus `reason`) from a pasted program or a wish; see "Programs and proposals". `check` is `checkProgramValue`. | None: the proposal is `failed`. |
| `learn_place` | Keeps the equipment note of ONE place up to date from one sentence the user said (ADR-021, the second exception to ADR-002; only places). It writes that something is not at the place only when the person said so (ADR-032). Input: `{place: {name, equipment}, otherPlaces: [name], sentence}`. Output: `{changed: boolean, equipment: string (<=1500)}`. Never blocks a reply: scheduled (`jobs/places:learn`) (1) after a start request with feedback is saved (the sentence is the newest feedback; source `feedback`), (2) after a start request with a note or text and no feedback is saved (source `note`), both for the place of the proposal, and (3) after a user message in a thread that has `placeId` (source `chat`). Code writes `places.text` only when `changed` is true, the text differs and the stored text is still the one the job read (a newer edit wins), and logs a `placeChanges` row with the source and the quote (the sentence, cut to 300) | No change. |
| `build_dashboard` | ordered module specs | sessions, active days, top set of most-trained exercise, one goal_progress per active goal, recent_sessions |
| `coach_turn` | One chat turn with functions (ADR-032): `{ message (1..4000), actions: [{ id (1..40), name, arguments }] (0..12, a union by name), question?: { text (1..500), answers?: [{ id, label (1..60)}] (0..6) } }`. Input: the `chat` context block and history, plus INPUT_JSON in the last user message: `screen`, `openSession` (`{ id, activity, focus?, planNote?, place, exercises: [{ id, name, measure?, sets: ["10x40 done"], coachNote?, commentFromThePerson?, personsWork }] }` or null), `currentExercise?`, `sessionPlace?`, `placeInView?`, `places: [{ placeId, name, equipment, knowledge, isSessionPlace? }]`, `entryInView?`, `programsThePersonFollows?`, `attachedToThisMessage?`; `goalsYouMayChange?`, `limitsYouMayChange?` (rules as kind and text only, no exercise lists, no records; the records are read in the `chat` context block, ADR-033), `notesYouMayChange?` (each with its `id`) and, from the context, `goalInView?`, `limitInView?`, `noteInView?`, `bodyPartInView?`; in the log chat also `today`, `now` and `currentLogDraft?`. The action `propose_program` `{ brief (1..1000), programId? }` is a proposal (ADR-032, step E): it starts a program proposal (see "The flow" under programs below), a change when `programId` (or `context.programId`, or the thread's `about.id`) names a live program, else a new program; an unknown program is rejected ("no such program"); one proposal per turn. On the screen `program` (or a thread with `about`) INPUT_JSON also holds `today`, `programInView?`, `programYouProposedAndThePersonSees?` and `aProgramProposalIsBeingWritten?`. The action `draft_log` is a draft until Done, in any chat (ADR-032, step D): `{ kind?: string (a category as in `read_entry`; needed in the log chat only; the turn input holds `categoriesInUse` in the log chat), color? (#RRGGBB, new category only; the stored draft and the app view carry the stored `color`), summary (1..120), at?: ISO date-time, session?: import draft shape, goal?: goal create shape, limit?: limit shape without `limitId`, note?: { text, topic }, edits?: { goalId?, limitId?, noteId? } (the existing goal, limit or note the part changes) }`. Outside the log chat only `goal`, `limit` and `note` are drafted (no `kind`, no `session`, no entry); a draft with none of them is rejected with a reason. `check`: action ids unique, no exercise an avoid rule names. | fixed "coach not available" message, no action, nothing changed. In the log chat (`screen: "log"`) the fixed message says so and the server makes a plain note draft (kind `other`); with an AI that fails after the retry the reply has no draft. |
| `parse_log` | Structure of one text-logged session (ADR-018). Input: `{activity, text, today (date and weekday), exercisesTheUserKnows: [{name, lastSets, measure?}]}` (from `coachPicture`). Output: `{minutes?, distanceKm?, focus?, date? (YYYY-MM-DD), exercises?: [{name, measure?: "time", sets?: [{reps, kg} \| {minutes, distanceKm?}]}]}`. Scheduled by `commands/sessions:logText`. Patches only `minutes`, `distanceKm`, `focus`, the day of `startedAt/endedAt` (time of day kept; a future day or one more than a year back is ignored) and `exercises` (then `kind` becomes `gym`), sets `parse` to `done`, then schedules the facts-changed rebuild and the review like `save`. An exercise named without sets gets the sets of its last logging in plain code; one that is not in the log and has no sets is left out. Never changes `note`, `type` or `source`. Dropped when the session is gone, `parse` is no longer `pending` or the stored note is not the text read (the user edited it). Derived structure of the user's own text, not a new fact (ADR-002, ADR-018) | Minutes (`45 min`, `1h`, `1h30`, `1:10`) and km (`8 km`) by regex; `parse` is `failed` only when nothing was read |
| `summarise_thread` | Thread.summary (<=400 chars) | last user message truncated |
| `review_session` | Review | set counts and top sets vs previous session of the same activity and focus |
| `import_data` | Session[] / Goal[] / ContextItem[] from a text chunk or an image | nothing imported; job note says AI is required |
| `match_exercise` | Picks the public exercise (free-exercise-db, with two photos) that is the same movement on the same kind of equipment as the name the person logged. Input: `{exercise, candidates: [{id, name, equipment}]}` (the shortlist, at most 12, by word overlap). Output: `{id: string \| null, movement?: string (<=400, one sentence: equipment, start position, end position; used in the image prompt when there are no photos)}`. The job runs also with an empty shortlist (for `movement`); `check`: a non-null id must be one of the candidates. Only the exercise name and public list entries go to the provider. Not called when the shortlist is empty. Run by `jobs/exerciseArt:make`. | The id of the first candidate when its name equals the exercise name (ignoring case, punctuation and a plural s); else null. |

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
- Records in job inputs (ADR-033): `coach_turn` (in the context block, under the limit), `build_session`, `plan_session`, `review_session` and `build_program` carry the person's limits as `{ part, title, status, rules: [{kind, text}], records?: [{ title, date?, text, textWasCut? }] }`. At most 5 records per limit (newest first), at most 8000 characters per record; `textWasCut: true` says a text was cut. A cleared limit appears only when it has records, with `rules: []`. No AI function writes or changes a record.
- The AI writes a time exercise as `{"name", "measure": "time", "sets": [{"minutes"}], "note"?}` next to the normal form (jobs `plan_session`, `build_session`).
- The app's add-exercise sheet lists the exercises of the user's own log (most recently used first, the log's spelling) and nothing else.
  A new name asks "Sets and reps" or "Time"; a name from the log keeps the measure it had last time.

**Stored AI calls (Convex backend, ADR-027).** Every job run that reaches the provider is stored as one row in `aiCalls`: `{ at, job, provider, model?, system, messages: [{ role, content }], images: number, attempts: [{ raw?, error?, ms }], path: "ai" | "fallback", reason?, ms, ref?, actions? }`. Indexes `by_at`, `by_job`. For a `coach_turn` row `ref` is the turn id (the user message id) and `actions` is the result of each action, `{ actionId, name, status: "applied" | "drafted" | "rejected", reason?, detail? }`, written by `jobs/coachTurn:save` so a bad turn can be diagnosed. It holds the exact prompt, every attempt (a rejected first answer too, with the reason) and the outcome. Images are counted, not stored. A text over 200,000 characters is cut. Written by `jobs/aiCalls:save` from `lib/ai.ts`; a failed write never fails the job. `jobs/purge:run` erases a row 90 days after the call. The app does not read this table.

**Comment on an exercise (ADR-029).** An exercise of a session (both shapes) may carry `comment?: string` (1..1000): the person's words about that exercise in that session. `commands/sessions:save` stores it; the session queries return it. `build_session` gets it inside `recentSessions`, on the exercise line: `Dips: 10x0 (comment from the person: "...")`. `review_session` gets it as `commentFromThePerson` on the exercise. The app shows it in the session and in the recap, and does not show it when the exercise comes again.

**The open session (Convex backend, ADR-028).** Table `openSession`, at most one row: the session the person is doing now, in the app's local shape `{ id, kind: "gym", type, focus?, startedAt, source?, planNote?, placeId?, programId?, programWeek?, programSlot?, programKey?, exercises: [{ id, name, measure?: "time", note?, comment?, fresh?, carry?, sets: [{ reps?, kg?, max?, failed?, minutes?, distanceKm?, done: boolean, at? }] }] }` plus `rev` (grows by one on every write), `updatedAt` and `updatedBy: "app" | "coach" | "owner"`. It is not a fact: the session becomes a fact with `commands/sessions:save`.

| Function | Arguments | Returns |
|---|---|---|
| mutation `commands/openSession:put` | `{ token, session }` (at most 40 exercises, 30 sets each) | the new `rev`. Replaces the row, whatever session it held. The app sends it after every local change. |
| mutation `commands/openSession:clear` | `{ token, id }` | nothing. Removes the row when it holds the session `id`. Idempotent. The app sends it when the session is finished or discarded. |
| query `queries/openSession:get` | `{ token }` | `{ session, rev, updatedAt, updatedBy }`, or `{ session: null, rev: 0, updatedBy: null }`. The app subscribes and takes the server's copy only with no unsent local change and a newer `rev`. |
| internal mutation `jobs/openSession:replacePlan` | `{ id?, by: "coach" \| "owner", exercises: [{ name, measure?, note?, sets }], focus?, planNote? }` | the new `rev`, or `null` when nothing changed. An exercise with a done set or a comment of the person stays as it is; the rest is replaced. |

## Providers

`AI_PROVIDER=anthropic | openai | deepseek | mock`. One interface:
`complete({ system, messages, images?, json: boolean, maxTokens }) -> string`.
Model names come from env (`ANTHROPIC_MODEL`, `OPENAI_MODEL`, `DEEPSEEK_MODEL`).
Optional methods: `transcribe` (see Voice message) and `image(prompt, photos) -> PNG bytes` (see Exercise art).
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

**The reader label (ADR-031).** `commands/entries:save` starts the job `read_entry` for a new entry and for one whose text or file list changed. The entry row holds `read: { status: "pending" \| "ready" \| "failed", rev: string, kind?: string, summary?: string (1..120) }`. `queries/entries:recent` returns `read: { status, kind?, summary?, made? }` on each item that has one (no `rev`). `made` (ADR-032) is `{ sessionId?, goalId?, limitId?, contextId? }`: the rows the log chat wrote with the entry when the person pressed Done. Job input: `{ when, text, photos: number, files: [{ name, text (<=6000) }] }` plus up to 4 images. `kind` is a dynamic category (ADR-031) with a colour: the table `entryCategories { key, label, color: "#RRGGBB", createdAt, source: "ai" \| "rules" }` holds one row per category, unique by `key` (the lower-cased label), and a colour never changes by itself. `queries/entries:recent` adds `read.color` from that table (absent while the label has no row; run `internal.jobs.migrations.categoryColors` once to give old labels a colour with no AI call). `kind` is a short label, one or two words, Title case, at most 24 characters. Job input also holds `categoriesInUse: [{ label, color? }]` (labels of the last 200 entries, most used first, then stored categories no recent entry uses); the AI reuses one when it fits. For a new category the AI may give `color` (`#RRGGBB`); the prompt carries a reference palette as guidance only. Code keeps the colour when it is `#RRGGBB` (upper-cased), else takes the first reference colour not in use, else cycles. For a category that exists the AI colour is ignored. Code trims, collapses spaces, cuts at 24 and matches a known label without regard to case. Old rows hold `meal`, `training`, `body`, `goal` or `other` and stay valid; `other` has no label. Output: `{ kind (1..60 before tidying), color?, summary }`. No code fallback: with no AI answer `status` is `failed`. The job writes only this label. In `logEntriesFromTheUser` an entry with files and a ready label carries `attachmentsShow: summary`.

Upload uses `commands/files:generateUploadUrl` and `commands/files:register`, as for chat.

**Session recap.**

| Function | Args | Returns |
|---|---|---|
| query `queries/sessions:load` | `{ token, sessionId }` | What one session loaded, for the body figure on its recap: `Record<muscleKey, 0 \| 1 \| 2 \| 3>` with every muscle key present, or `null` when the session is unknown. It uses the exercise-to-muscle table and the same level rule as the "About me" load (the busiest muscle of this session is the top: share >= 0.6 is 3, >= 0.25 is 2, above 0 is 1; a time exercise counts one set per 4 minutes). The code is shared (`model/rules/load.ts`, `loadForSession`). Additive: no stored row changes |

**Log by text (ADR-018).** `commands/sessions:logText { token, sessionId, type (1..40), text (1..1000, not blank), at: number }` is an idempotent insert by `sessionId`: the same id again changes nothing and schedules nothing. It stores a session as a fact: `kind: "activity"`, `type`, `startedAt = endedAt = at`, `exercises: []`, `note: text` (word for word), `source: "app"`, `parse: "pending"`, and schedules `parse_log`. The app's session subscriptions (`queries/sessions:recent`, `since`) return `parse`, so the recap updates when the structure arrives. `commands/sessions:save` accepts a session that carries `parse` but never stores it: a resend of an unchanged session keeps the stored `parse`; a real edit clears it, so a late `parse_log` result is dropped.

A past session is corrected with the same `commands/sessions:save` (an idempotent upsert by `sessionId`): the app sends the full session again with its `sessionId`, `kind`, `source` and `importId` unchanged. A changed session schedules a new review. 

**Delete marks, then purges (ADR-020).** `commands/sessions:remove { token, sessionId }` and `commands/entries:remove { token, entryId }` only mark the row: they set the optional `deletedAt` (epoch ms, the time of the first call; a second call keeps it) and return `true` when this call marked it, `false` when the row is unknown or already marked. Nothing else goes at that moment, not the review of a session and not the files of a note. A session's mark also asks for a rebuild of the read models. A marked row is invisible to every read: the queries, the jobs, the coach picture, the chat context, dashboards, plans, reviews and load levels. A `commands/sessions:save`, `logText` or `commands/entries:save` for a marked id changes nothing and returns the id, so a late resend from an offline phone does not bring it back. A pending `parse_log` or review result for a marked session is dropped. An hourly cron (`crons.ts`, `jobs/purge:run`) erases every row marked more than 72 hours ago (`DELETE_AFTER_MS`), in batches of 50: a session with its review, a note with its file rows and blobs, a program as it is (the sessions logged on it stay). The operator can undo a delete within 72 hours with the internal functions `commands/sessions:restoreSession { sessionId }` and `commands/entries:restoreEntry { entryId }` (run with `npx convex run`; there is no app screen for it). The app asks for confirmation before it removes a session or a note, and says that the erasing follows after 72 hours.

Coach: `coachPicture` (the `build_session` input) has a field `logEntriesFromTheUser`: the entries of the last 7 days, oldest first, at most 20, each `{ date, time, text, attachments: number }`. The chat context lists the same entries. The image files of entries of the last 24 hours (at most 4, newest first) go with the `build_session` request and the chat request when the provider takes images; DeepSeek has no image input, so no image is sent there.

## Programs and proposals (Convex backend)

A program is a plan over several weeks that the person agreed to: phases, the sessions of each phase, rules and tests. The coach only PROPOSES it. A proposal is a generic frame ("the coach proposes, the person agrees"); a program is its first kind. The session start has no program entry of its own (ADR-030): `build_session` gets `programsThePersonFollows` (every active program that runs today: the week, the phase, `slotsThisWeek` with done or not, `sessionsAsWritten`, the rules, the tests) and builds the session from it. When the coach says which program session it built (`program: {programId, key}`), `jobs/startRequest:save` finds the week and the first open slot with that key and stores `program: {programId, week, slot, key}` on the proposal; the app writes these as `programId`, `programWeek`, `programSlot`, `programKey` on the session. `queries/programs:list` still returns `now.next` (the written session with the kg of the last time); the app no longer starts a session from it.

```ts
ProgramSession { key: string 1..12, title: string 1..40, activity: string 1..40, exercises: PlanExercise[] 1..14, note?: string <=200 }
ProgramPhase   { title: string 1..40, weekFrom: int >=1, weekTo: int >=weekFrom, note: string <=400 (may be ""), sessions: ProgramSession[] 1..8 }
ProgramValue   { title: string 1..60, purpose: string <=300, startsOn: "YYYY-MM-DD", endsOn: "YYYY-MM-DD",
                 week: string[] 1..10 /* session keys of ONE week, in order; a key may repeat (A, B, A) */,
                 phases: ProgramPhase[] 1..8, rules: string[] 0..12 (each <=300), tests: string[] 0..12 (each <=200) }
```

`PlanExercise` is the plan exercise of the plan schema (sets `{reps, kg, max}`, or `measure: "time"` with `{minutes}`; `note` max 120).

**Validity** (`checkProgramValue(value, limits)` in `model/program.ts`; the `build_program` job uses it as `check`, and `commands/proposals:accept` runs it again with the limits of that moment). It returns a plain sentence or `null`. The dates are real; `endsOn >= startsOn`; the program lasts at most 26 weeks, where `weeks = ceil(days / 7)` and both end days count (1 Dec to 7 Dec is one week; 1 Dec to 8 Dec is two). The phases are in order, start at week 1, have no gap and no overlap, and cover every week. Every key of `week` is a session of EVERY phase. Session keys are unique inside a phase. No exercise is one that a limit marks avoid.

| Table | Fields |
|---|---|
| `programs` | `{ programId, title, purpose, startsOn, endsOn, week, phases, rules, tests: [{ testId, text, doneOn?: "YYYY-MM-DD" }], status: "active" \| "paused" \| "done", sourceText?, rev, createdAt, updatedAt, deletedAt? }`. Indexes `by_programId`, `by_deletedAt`. `rev` is 1 on insert and +1 on every change. A delete marks `deletedAt` (ADR-020): a marked program is invisible to every read, and `jobs/purge:run` erases it 72 hours later. The sessions logged on it stay. |
| `proposals` | `{ proposalId, target: { kind: "program", id?: string }, value?: ProgramValue, reason?: string <=200, base?: number, approval: "none" \| "explicit", origin: "request" \| "feedback" \| "chat", status: "building" \| "ready" \| "applied" \| "declined" \| "stale" \| "failed", source?: "ai" \| "rules", ask: { text?, feedback?: string[], previousProposalId? }, error?: string <=200, threadId?: string, messageId?: string, createdAt, decidedAt? }`. Indexes `by_proposalId`, `by_createdAt`, `by_threadId`. `threadId` and `messageId` are set on a proposal made in a chat (`origin: "chat"`, ADR-026): the thread and the assistant message it came from. `target.id` absent means a new program; present means a change of that program, and `base` is its `rev` when the proposal was made. `approval` and `origin` are set by server code (`model/proposalPolicy.ts`, `approvalFor(kind, origin)`: a program is always `explicit`), never by the client. `value` is set when the status is `ready`. Removed after 7 days. |
| `sessions` | new optional `programId`, `programWeek` (int >=1), `programSlot` (int >=1), `programKey` (1..12) |

| Function | Args | Returns |
|---|---|---|
| mutation `commands/proposals:request` | `{ token, proposalId (1..100), kind: "program", targetId?, text? (1..8000), feedback? (1..1000), previousProposalId? }`. Either `text` (a new ask) or `feedback` with `previousProposalId` (a rebuild; they go together). A rebuild copies the target and `ask.text` of the previous row, appends the feedback (at most 5 rounds, oldest dropped) and sets the previous row to `declined`; the previous row must exist and be `ready`. A given `text` or `targetId` is ignored in a rebuild. With `targetId` the proposal is a change of that program (it must exist; `base` = its `rev`). | the proposalId. Idempotent by proposalId. Inserts status `building` and schedules `jobs/programs:build`. Deletes proposals older than 7 days. Errors are `ConvexError`. |
| mutation `commands/proposals:accept` | `{ token, proposalId }`. Only a `ready` proposal. | `{ programId }`. Checks the value again with the current limits (the reason is thrown). A new program is inserted `active`, `rev` 1, `sourceText` = `ask.text`, tests with fresh ids; its `programId` is the proposalId. A change needs the program to exist with `rev === base`, else it throws "The program changed. Ask again."; it replaces the value, keeps `programId`, `status`, `createdAt` and the `doneOn` of a test whose text did not change, and sets `rev + 1`. The proposal becomes `applied`. Asks for a rebuild of the read models. When the proposal has a `threadId` and that thread's `about.id` is not set, the thread gets `about.id = programId`, and its title becomes the program title when `titleSource` is `auto`. |
| mutation `commands/proposals:decline` | `{ token, proposalId }` | `null`. A `building` or `ready` proposal becomes `declined`; any other is left alone. |
| query `queries/proposals:get` | `{ token, proposalId }` | `{ proposalId, target, status, approval, origin, value: ProgramValue \| null, reason: string \| null, source: "ai" \| "rules" \| null, error: string \| null }` or `null`. |
| query `queries/proposals:open` | `{ token }` | the newest proposals with status `building` or `ready` and approval `explicit` (at most 5, same item shape). The app uses it to show a waiting proposal after a restart. |
| query `queries/proposals:forThread` | `{ token, threadId }` | the proposals of that thread (`threadId`), oldest first, at most 50, each in the SAME shape as `queries/proposals:get` (with the derived `stale`). The app subscribes to it while the thread is open and matches a proposal to its message through `messages.proposalId`. |
| mutation `commands/programs:setStatus` | `{ token, programId, status: "active" \| "paused" \| "done" }` | `null`; `rev + 1` when the status changes. An unknown program is an error. |
| mutation `commands/programs:remove` | `{ token, programId }` | `null`; marks `deletedAt`. Idempotent. |
| query `queries/programs:list` | `{ token }` | every live program, newest first: `{ programId, title, purpose, status, startsOn, endsOn, week, phases, rules, tests, rev, now }` where `now = { state: "before" \| "running" \| "ended", week: int, weeks: int, phaseIndex: int, slots: [{ slot, key, title, done }], next: { slot, key, title, activity, exercises: PlanExercise[], note? } \| null }`. See below. |
| mutation `commands/sessions:save` | the session may carry `programId`, `programWeek`, `programSlot`, `programKey` | as before. The four fields are stored as given. A save WITHOUT `programId` (an old app build) keeps the stored link. |
| mutation `commands/start:request` | `previousPlan` form | see the Endpoints table. |

**The `now` block.** Today is the local date in `APP_TIMEZONE` (UTC when not set). `state` is `before` when today is before `startsOn`, `ended` when it is after `endsOn`, else `running`. `week = floor(daysSince(startsOn) / 7) + 1`, clamped to `1..weeks`. `phaseIndex` is the phase that holds that week. `slots` are the places of THIS program week in the order of `week`, numbered from 1 (a repeated key is a separate slot: A, B, A are slots 1, 2, 3). A slot is `done` when a live session has this `programId`, `programWeek === week` and `programSlot === slot`. `next` is the first slot that is not done; it is `null` when the state is not `running`, when the status is not `active`, or when every slot is done. `next.exercises` is the written session of the current phase with the kg filled in by plain code (`fillKg`): for an exercise with sets, the kg of the LAST set of the same exercise name (case and outer space ignored) in the newest live session with the same `programId` and `programKey`; else in the newest live session of the whole log that has that exercise; else the written kg. Reps, set count, order, notes, the `max` flag and time exercises stay as written. The app starts the session with these exercises and sends `programId`, `programWeek` = `now.week`, `programSlot` = `next.slot` and `programKey` = `next.key` when it saves the session.

**A stale change.** A thrown mutation keeps no write, so `accept` cannot store `stale` itself. `queries/proposals:get` reports a `ready` change proposal as `status: "stale"` when its program was deleted or has another `rev` than `base`, and `queries/proposals:open` leaves it out. The stored row stays `ready`.

**AI job `build_program`** (`model/ai/jobs/buildProgram.ts`, run by `jobs/programs:build`). Same pipeline as the other jobs (JSON, zod, `check`, one retry), with a budget of 150 seconds and 16000 output tokens. Input: `{ today, request, feedbackFromThePerson?, previousProgram?, currentProgram?, goalsInOrderOfPriority, limits, placesTheCoachKnows: [{name, equipment}], exercisesTheUserKnows: [{name, lastSets, bestKg}] (at most 60) }`. `limits` carry the person's records (ADR-033). `previousProgram` is the value of the previous proposal on a rebuild; `currentProgram` is the program as it is now when the proposal changes one. Output: `ProgramValue` plus `reason` (<=200). There is no code fallback (a program cannot be made by rules): when the AI fails, the proposal is `failed` with a short `error`. The mock provider answers with a small fixed valid program.

## Chat about a program (Convex backend, ADR-026)

A program is asked for, discussed and changed in a chat thread that is about the program. The coach's proposal shows in the chat as a card with Agree and Cancel. A thread with `about` is hidden from the chat list by the app by default.

**Schema (all optional, additive).** `threads.about?: { kind: "program", id?: string }` (no `id`: a new program that is not agreed yet). `messages.proposalId?: string` (only on an assistant message; the proposal may be gone after 7 days, then the app shows no card). `proposals.threadId?`, `proposals.messageId?` and the index `by_threadId` (see the `proposals` row above). `threads.placeId` stays as it is.

| Function | Args | Returns |
|---|---|---|
| mutation `commands/threads:create` | `about?: { kind: "program", id? (1..100) }` | With an `id` the program must exist, else `ConvexError` "program not found". Stored as given; ignored on a resend. Without a title the thread is called "New program" (no `id`) or by the program's title, `titleSource: "auto"`. The automatic title (`title_thread`, and the title from the first message) does not run for a thread with `about`. The app finds the thread to reuse (one per program id; one new-program thread with no applied proposal). |
| query `queries/threads:list` | as before | each thread may carry `about`. The app filters. |
| query `queries/threads:list` | as before | a thread may carry `openSessionId`: the `context.openSessionId` of its first user message (set once by `commands/messages:send`, never changed). The app opens the newest thread with the id of the open session again, also after a restart. Threads from before this have none. |
| query `queries/messages:list` | as before | an assistant message may carry `proposalId`. |
| query `queries/proposals:forThread` | `{ token, threadId }` | see the proposals functions above. |
| mutation `commands/programs:remove` | as before | also removes the thread about that program (`about.id`) and its messages, as `commands/threads:remove` does. Its proposals stay and are removed after 7 days. |

**The flow.** The person writes, speaks or attaches files with the ordinary `commands/messages:send` and `sendVoice`. `jobs/coachTurn:run` answers it with the job `coach_turn` (AI jobs table; the old jobs `chat_program` and `chat` are gone). `jobs/coachTurn:save` stores the assistant message. When the turn holds the action `propose_program`, the same mutation (`lib/programChatDb` `startProgramProposal`): marks the thread's `building` and `ready` proposals `declined`; inserts a proposal `{ target: { kind: "program", id?: about.id }, base?: the program's rev, approval: approvalFor("program", "chat"), origin: "chat", status: "building", threadId, messageId, ask }`; sets `messages.proposalId`; schedules `jobs/programs:build`. If the program of `about.id` is gone, no proposal is made. The model only says what to write; code does the action. No provider tool API (ADR-005).

`ask.text` (at most 8000 characters) is the texts of the person's messages in the thread, oldest first, joined with a blank line and cut from the start so the newest text stays, then `\n\nThe coach's summary of what to write: <brief>`. When the thread has a `ready` proposal with a value, that proposal is the previous one: the new row has `ask.previousProposalId` and `ask.feedback` = its feedback plus the brief (at most 5), so `build_program` gets `previousProgram` and `feedbackFromThePerson`. Feedback is the next chat message; there is no feedback endpoint. "Agree" is `commands/proposals:accept` (plain code, no AI call; a second agree of an applied proposal changes nothing and returns the same `{ programId }`), "Cancel" is `commands/proposals:decline`.

**Files.** When the proposal has a `threadId`, `jobs/programs:build` also loads the files of the thread's user messages (newest 6, not audio) like the coach turn does. The input of `build_program` then has `attachedFiles: [{ name, text }]` (text of documents, each cut at 12000 characters) and `attachedImages: [name]`; the images go to the provider when it takes images. A photo of a paper program works. Without `threadId` nothing changes.

**What does not run.** No title job and no extraction run in any chat: nothing is written silently from a pasted program. `summarise_thread` still runs. A voice message needs no new path: the transcript becomes the message text, then the same reply job runs.

**Still in use.** `commands/proposals:request`, `queries/proposals:get` and `queries/proposals:open` have no caller in the current app (it uses `forThread`, `accept`, `decline`); they stay for now (the 7-day removal of proposals lives in `request`). The 7-day removal of proposals stays.

## Places (Convex backend, ADR-021)

A place is a fact: where the user trains and what is there, in free text (`Place` in the schema). The user never has to make one. The coach picks today's place for a proposal, and a background job learns the equipment text from the user's own words. All fields are optional and old app builds keep working.

| Function | Args | Returns |
|---|---|---|
| query `queries/places:list` | `{ token }` | `[{ placeId, name, text, updatedAt }]`, sorted by name |
| mutation `commands/places:save` | `{ token, placeId (1..100), name (1..30 after trim), text? (0..1500) }` | the placeId. Idempotent upsert by placeId. `text` left out keeps the stored text. Rejects a name whose key (trim, lower case, inner spaces collapsed) belongs to another placeId. A change of the text logs a `placeChanges` row with source `user`. |
| mutation `commands/sessions:setPlace` | `{ token, sessionId, placeId: string (1..100) \| null }` | `true`; `false` when the session is unknown or marked as deleted. Sets or clears the place of that one session; nothing else on the row changes and no rebuild or review is scheduled. The id is stored as given. |
| mutation `commands/sessions:save` | the session may carry `placeId` | as before. A save WITHOUT `placeId` (an old app) never erases the stored one. |
| mutation `commands/threads:create` | `{ token, threadId, title?, placeId?, about? }` | as before. `placeId` (1..100) says the conversation is about that place. A resend changes nothing. `queries/threads:list` returns `placeId` when set. `about` is described under "Chat about a program". |
| query `queries/sessions:recent`, `queries/sessions:since` | as before | each session carries `placeId` when set |
| query `queries/start:request` | as before | `proposal.place: { placeId, name }` when a place is known |

How the place of a proposal is set (`jobs/startRequest:save`, plain code): the name the coach gave is matched to a place by its key; a new name makes a place with an empty text; when the coach gave none, or on the rules fallback, the place of the newest live session of the same activity is used (none when that session has no place, or its place is not stored). `build_session` input and output are in the AI jobs table.

Chat: when the thread has `placeId` and the place exists, the coach turn reads it as `placeInView` and every place with its text, and the coach changes the text itself with `update_place` (evidence: the person's words or a photo of the turn). A place text goes to the AI provider; a record goes too (ADR-033). `commands/messages:send` no longer schedules `learn_place`; that job now runs only from the Start request (`jobs/startRequest.ts`).

Seed (once, by the operator, idempotent): `internal.jobs.places:seed {}`. It makes the place "Gym" with the text of the active context item(s) whose topic is "equipment" and sets those items inactive (so the equipment is not sent twice), logs a `placeChanges` row with source `seed`, makes the place "Home" with an empty text, and gives every live session with no place a place: activity "Gym" (an old flavour name counts as Gym) to Gym, "Home" or a name that starts with the word home to Home, other sessions stay as they are; sessions marked as deleted are not touched. At most 2000 sessions per run; `remaining` in the result tells if another run is needed. Returns `{ gymCreated, homeCreated, equipmentMoved, sessionsGym, sessionsHome, remaining }`. A second run changes nothing.

## One chat with functions (Convex backend, ADR-032, step A)

Every message is answered by the coach turn: a reply plus functions that server code does at once. All fields are optional and additive; old app builds keep working.

| Function | Args | Returns |
|---|---|---|
| mutation `commands/messages:send` | `{ token, threadId, messageId, text, fileIds?, context?: {...}, answer?: { turnId: string (1..100), id: string (1..40) } }` (each context id 1..100; `context.screen` is one of `chat`, `log`, `session`, `exercise`, `goal`, `limit`, `note`, `program`, `start`; the other context fields are `openSessionId`, `exerciseId`, `placeId`, `entryId`, `programId`, `goalId`, `limitId`, `noteId` and `part` (a body part key)). `answer` says the message is a tap on a quick answer of the coach: `turnId` is the `turnId` of the assistant message that asked. `id` `"approve"` on a message that holds a stored `proposal` applies it in plain code with no AI call, stores the user message and a fixed assistant message ("Done. The session is rebuilt.", or "This plan was applied already. Nothing more changed.", or "I could not apply this plan: <why>. Nothing was changed. ..." with an action `rejected` and a `reason`), and schedules nothing. Any other `id`, or no stored proposal, runs the normal coach turn with the text | the messageId, as before. `context` is stored on the user message. With `screen` `"chat"`, `"log"`, `"session"`, `"exercise"`, `"goal"`, `"limit"` or `"note"` (and for an answer to a coach question) it schedules `jobs/coachTurn:run` (and not `learn_place`); a message with no `screen`, or from `"program"` or `"start"`, schedules `jobs/chat:reply` as before (ADR-032 step D). A resend after a failed reply runs the job of the stored context. |
| query `queries/messages:list` | as before | a user message may carry `context`. An assistant message of a coach turn carries `turnId` (the user messageId it answers), `actions: [{ actionId, name, status: "applied" \| "drafted" \| "rejected", reason?, detail? }]` and `question?: { text, answers?: [{ id, label }] }`, and, for a whole-session change, `proposal?: { title?, exercises: [{ name, sets: string }], state: "open" \| "applied" \| "stale" }`. `sets` is a short text: "3 × 10", "3 × max", "10, 8, 6", "3 × 30 s", "10 min". When every set has the same non-zero weight, `sets` ends with it ("3 × 10 · 40 kg"); otherwise the weight is left out. `detail` (max 120) is a plain line made by code, never by the model, from the checked arguments and the data at that moment: replace "Tandem Stand → Balance Board", or for the same name "Balance Board: note and sets changed" (note, sets or both); add "Added: Wall Sit, 3 × 30 s"; remove "Removed: Brisk Walk"; `update_place` "Gym: added balance board" or "Gym: removed second bike" (both: "Gym: added a, removed b"); `rebuild_open_session` "Proposed: 7 exercises". A rejected action has `reason` and no `detail`. `state` is `applied` once approved, `stale` when a newer proposal came later in the thread or the open session is another one (or none), else `open`. The message with a proposal always has `question.answers` `[{ id: "approve", label: "Approve" }, { id: "change", label: "Change something" }]`, set by the server. A quick answer is sent with `answer` (and its label as `text`). |
| action `jobs/coachTurn:run` (internal) | `{ threadId, messageId }` | Reads the chat input plus the screen (the server's open session, the exercise in view, the session's place, every place, the entry in view, the programs), runs `coach_turn`, then `jobs/coachTurn:save`, then `summarise_thread`. Every message runs it (a message with no screen, or from `start`, counts as `chat`); no title job and no goal or note extraction run. A thread with `about.kind === "program"` is the screen `program`. The thread's `placeId` is the `placeInView`. An unexpected error fails the reply (`jobs/chat:fail`). |
| mutation `jobs/coachTurn:save` (internal) | `{ threadId, turnId, openSessionId?, rev?, message, actions, question?, sources, plainLog?, screen?, plainPart? }` | the action results, in one transaction with the assistant message. A second save of the same `turnId` changes nothing and returns the stored results. |

**The functions ("applied at once", except the whole-session proposal).** Each action is parsed again with zod and checked against the data now. A refused action changes nothing and gives a `reason`. All but `rebuild_open_session` are applied at once.

- `update_place { placeId, add?, remove?, evidence: "person_said" | "seen_in_photo" }`: removes the phrase `remove` (any case) and adds `add` on a new line unless the text names it. `person_said` needs text in the user message of the turn; `seen_in_photo` needs an image attached to it. Writes the place (`knowledgeState: "partial"`) and a `placeChanges` row `{ source: "chat", evidence, quote: the person's message (cut to 300) }`. Refused over 1500 characters.
- `replace_open_exercise { exerciseId, exercise }`, `add_open_exercise { exercise, afterExerciseId? }`, `remove_open_exercise { exerciseId }`: on the open session. `exercise` has the plan exercise shape. Refused for an exercise with a done set or a comment of the person, an unknown id, a name already in the session, or no set. Other exercises stay exactly as they are. A replaced or added exercise gets a new id.
- `rebuild_open_session { title? (1..60), exercises (1..), focus?, planNote? }`: a PROPOSAL for the whole unfinished plan. Nothing is written. The result is `drafted`; the checked plan is stored on the assistant message (`proposal { title?, exercises, focus?, planNote?, rev, openSessionId, appliedAt? }`; the app gets the view in `queries/messages:list`). Only one per turn (a second is `rejected`). On approve the plan is checked again and merged as `jobs/openSession:replacePlan` does (the person's work stays at the front); the open session gets `rev + 1`, `updatedBy: "coach"`.
- Every exercise a function writes gets the plan safety limits and the avoid rules (`finalizePlan`); an avoided exercise is refused. The session functions are refused when no session is open, another session is open, or its `rev` changed since the turn read it. The open session is written once per turn with `rev + 1` and `updatedBy: "coach"`. No function changes `placeId`.

**Places.** `places.knowledgeState?: "partial" | "unknown"` (absent: `"partial"`, an empty text is always `"unknown"`); `placeChanges.evidence?: "person_said" | "seen_in_photo"`. `queries/places:list` does not change. `build_session` and `build_program` get `knowledge` on each place; every prompt with places says that a place text is never a full list and that equipment not named is unknown, not missing.

## Voice message in the chat (Convex backend)

The user records speech; the server turns it into text. Since ADR-034 the app asks for the text with `commands/voice:transcribe` and puts it in the text field; the person sends it as a typed message. The older path below (`sendVoice`, `retryVoice`, `jobs/voice:transcribe`) stays for older app builds: the message is then a normal text message and the coach answers as usual. All changes are additive; old app builds are not affected.

| Item | Contract |
|---|---|
| Upload | The existing flow: `commands/files:generateUploadUrl`, then `commands/files:register`. A file with mime `audio/*` (or an m4a, mp3, wav, aac, ogg, opus name) gets kind `"audio"`. The app records AAC in `.m4a` (`audio/mp4`), max 180 s. |
| mutation `commands/messages:sendVoice` | `{ token, threadId, messageId (1..100), fileId }` returns the messageId. Idempotent by messageId (a second call changes nothing). Rejects an unknown thread, an unknown file, a file that is not kind `audio`, and a file over 10 MB, with a `ConvexError`. Inserts a user message `{ text: "", fileIds: [fileId], voice: "pending" }`, sets the thread to `thinking` with `pending + 1`, and schedules `jobs/voice:transcribe`. A resend of the messageId through `messages:send` never starts a coach run for a voice message that is not `done`. |
| action `jobs/voice:transcribe` (internal) | Reads the blob and calls the provider's `transcribe`. Success with a non-empty text: stores the trimmed text (max 8000 characters, like a typed message) and `voice: "done"`, then schedules the same work as `messages:send` (`jobs/coachTurn:run`). The unnamed thread gets its code title from the transcript. The `pending` count is not raised again. An empty transcript, a provider error, a provider without `transcribe`, or a missing blob: `voice: "failed"`, `pending - 1`, status `idle` (`thinking` while other replies run), no coach reply. A run for a message that is no longer `pending` does nothing, so the reply is scheduled once. The log holds only a short reduced text (`HTTP 401`, `timed out`), never a provider message. |
| action `commands/voice:transcribe` (public, ADR-034) | `{ token, fileId }` returns `{ ok: true, text }` or `{ ok: false, reason }`. The file is an uploaded recording (kind `audio`, as in Upload). It does not store a message, does not change a thread and does not start the coach: the app puts the text in the text field and the person sends it with `messages:send`. Success: the text is trimmed and at most 8000 characters, and the audio file (storage blob and `files` row) is removed. Failure: `reason` is a short reduced text (`The recording is gone.`, `The AI provider cannot transcribe.`, `No speech was heard.`, `The provider answered HTTP 401.`), never a provider message, and the file stays for a retry. A wrong token throws `unauthorized`; a file over 10 MB throws a `ConvexError`. The core is `lib/transcribe.ts`, shared with `jobs/voice:transcribe`. |
| mutation `commands/messages:retryVoice` | `{ token, messageId }` returns `true` and does for a message with `voice: "failed"`: sets `voice: "pending"`, thread `thinking` with `pending + 1`, schedules the transcription again. Returns `false` for any other message or an unknown id. |
| `messages.voice` | Optional `"pending" \| "done" \| "failed"`. `queries/messages:list` returns it when set. Absent on a typed message and on an assistant message. |
| Coach input | `jobs/coachTurn:input` returns nothing for a message that is `pending` or `failed`. A voice message without a transcript is left out of the history of other replies and of the thread summary. A file of kind `audio` is never a coach file: not as text, not as an image, not in `sources`. Only the transcript (the message text) reaches the model. |
| Provider | Optional `transcribe(bytes, mime, filename): Promise<string>`. OpenAI: `POST {base}/v1/audio/transcriptions`, multipart form with `model` and `file`, answer `{ text }`, timeout 60 s. The model is the env `OPENAI_TRANSCRIBE_MODEL`, default `gpt-4o-transcribe`. Anthropic and DeepSeek have none. The mock returns a fixed text (a file named `silence...` gives an empty one). |

## Exercise art (Convex backend)

Every exercise gets one picture with two key poses side by side. The server makes it once per exercise name and stores it. The app shows the left half, then the right half, in a loop. The server does not cut the image.

Key of an exercise: `name.trim().toLowerCase()` with runs of white space made one space (max 80 characters).

| Item | Contract |
|---|---|
| Table `exerciseArt` | `{ key, name, status: "pending" \| "ready" \| "failed", storageId?, sourceId?, model?, shift? { dx, dy }, tries?, error? (<=300), createdAt, updatedAt }`. `shift` and `tries` come from the check below. Indexes `by_key`, `by_updatedAt`. |
| mutation `commands/exerciseArt:request` | `{ token, names: string[] }` (1..12 names, each 1..80 after trim; else a `ConvexError`). A name with no row gets a `pending` row and a `jobs/exerciseArt:make` run. A `failed` row older than 24 hours goes back to `pending` and runs again. Other rows stay. At most 40 new or retried rows in the last 24 hours (rows counted by `updatedAt`); names over the cap are skipped silently. Idempotent. Returns `null`. |
| query `queries/exerciseArt:get` | `{ token, names: string[] }` (0..30) returns `[{ name, status: "none" \| "pending" \| "ready" \| "failed", url: string \| null }]`, one item per name, same order. `url` is the storage URL when the status is `ready`, else `null`. |
| Image | PNG, 1536x1024, two panels of equal width: left = start position, right = end position. |
| action `jobs/exerciseArt:make` (internal) | Stops when the row is not `pending`. Shortlist of the public exercise list (`model/data/exerciseSources.json`, 873 entries of free-exercise-db, public domain) by word overlap, then job `match_exercise`. With a match it fetches the two public photos (`.../exercises/<id>/0.jpg` start, `1.jpg` end); a failed photo fetch means: go on without photos. Muscles come from the matched entry, else from `musclesFor(name).primary`. It calls `provider.image`, stores the PNG, and sets `ready` with `storageId`, `sourceId` (when matched) and `model`. Any error, or a provider with no `image` method, sets `failed` with a short `error`. It never throws. Only the exercise name and the public photos go to the provider. |
| Check: the figure stays in place | After each image call, code measures the picture (`model/poseShift.ts`): how far the end pose (right half) must move so that the parts that do not move sit on the start pose (left half). The result is `shift { dx, dy }` in parts of the width and height of one half. More than 0.03 on one axis counts as a jump. Then the job draws again with the same prompt, at most 3 pictures in one run, and keeps the steadiest. The row stores the `shift` of the kept picture and `tries`. A picture the code cannot read is taken as it is. Real pictures in `tests/fixtures/art-*.png` fix what the check must say. The app measures the same way and moves the end pose back, so a picture that still jumps a little shows steady. |
| Auto request | When `jobs/startRequest:save` stores a proposal with a plan, it requests art for the exercise names of the plan (at most 12) through the same logic as the command, with the same daily cap. |
| Provider | Optional `image(prompt, photos: [{bytes, mime}]): Promise<Uint8Array>`. OpenAI only. With photos: `POST {base}/v1/images/edits`, multipart with `model`, `prompt`, `size=1536x1024`, `quality=medium` and one `image[]` part per photo. Without photos: `POST {base}/v1/images/generations`, JSON `{ model, prompt, size, quality }`. Both answer `{ data: [{ b64_json }] }`. Timeout 180 s. The model is the env `OPENAI_IMAGE_MODEL`, default `gpt-image-2`. Anthropic and DeepSeek have none. The mock returns a few fixed bytes (model `mock-image`). |

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

## Log chat (Convex backend, ADR-032)

A message sent with `context.screen === "log"` runs the coach turn (`commands/messages:send`). Its text may be empty when `fileIds` is not. The log chat is one thread per log.

- The assistant message of a turn that drafted a log holds `proposal` = `{ type: "log", kind, summary, at (ms), session?: { type, focus?, minutes?, distanceKm?, exercises: [{ name, sets: "3 x 10" }] }, goal?: { title, kind, exercise?, targetKg?, sessionsPerWeek? }, limit?: { part, title, status, since?, rules }, note?: { text, topic }, state: "open" \| "applied" \| "stale", entryId? }`, `actions: [{ name: "draft_log", status: "drafted", detail }]` and `question: { text, answers: [{ id: "approve", label: "Done" }, { id: "change", label: "Add or change" }] }`. A whole-session proposal now also has `type: "session"`.
- The app sends the tap as `send` with `answer: { turnId, id }`. `approve` writes the entry and the rows in plain code, once, with no AI call. The reply is an assistant message with a fixed text ("Logged: dinner, pasta. Session added.") and `entryId`; the draft turns `applied` and holds `entryId`. A second `approve` changes nothing and says so. A draft with a newer proposal after it is refused with a reason. `change` runs a normal turn.
- The entry text is the person's messages of the thread up to the draft, joined by a blank line, unchanged (a tap on a quick answer is left out); `fileIds` are all their files (at most 10); `at` is the draft's. Its `read` is `{ status: "ready", kind, summary, made? }` and no `read_entry` job runs. The session has `source: "import"`, `importId` = the entry id; a goal, a note (`source: "ai"`) and a limit carry `importId` = the entry id.
- `commands/entries:remove` on such an entry also marks its session as deleted. The goal, limit and note stay.
- The coach does not read an entry that made a session in its entries list: the session is read as training.

## Goal, limit and note drafts (Convex backend, ADR-032 step D)

A message sent with `context.screen` `"goal"`, `"limit"` or `"note"` (or from the general chat, `"chat"`) runs the coach turn. The coach drafts with the same `draft_log` action and the same stored `proposal` (`type: "log"`) as the log chat; no new table or action.

- A draft with no `kind` in `draft_log` (a goal, a limit or a note only) has `noEntry: true`. Its `kind` is `"Goal"`, `"Limit"` or `"Note"` (no category row is made). A draft with a `kind` makes an entry from any chat (ADR-032, decision 2026-11-24); outside the Log tab the entry text and files come from the message that made the draft and the open drafts it replaced, not from the whole thread. `edits?: { goalId?, limitId?, noteId? }` marks a part that changes an existing row. Both fields are returned in the proposal of `queries/messages:list`.
- **One goal path.** The coach fills the structure fields of the goal (`kind`, `exercise?`, `targetKg?`, `sessionsPerWeek?`) under the same schema as a goal made by hand (`GoalInputSchema`). Code keeps `exercise` only when it is a name of the person's log, in the log's spelling (as the job `parse_goal` did). Done writes the finished goal; no reading job runs. The job `parse_goal` is gone. `commands/goals:create` and `update` are plain writes: they do not schedule any AI job, and a new title clears the old structure fields.
- With no AI answer, the goal chat drafts the person's words as the title, kind `custom`, and a number before `kg` and before "times a week" when present; the note chat drafts the words as a note with topic `general`. Done writes it.
- `approve` ("Done"): in plain code, once, with no AI call. A new part is added (`goalId`/`limitId`/`itemId` = `l-<turnId>-g|l|n`). A part with `edits` changes that row: a goal gets the whole new title and structure; a limit gets the new title, status, `since` and rules (a rule sent back with the same kind and text and no exercise list keeps the stored exercises; records and check-ins stay); a note gets the new text and topic. A row that is gone is skipped and the reply says so. No entry is written. The reply is a fixed text: "Goal added.", "Limit changed.", "Note added.". A second `approve` says "This was saved already. Nothing more changed."
- No function deletes. A request to delete is answered with where the person does it; every delete in the app asks first.
- Limits and goals are never applied without Done. The plan safety limits and the avoid rules of limits stay in code (ADR-004, ADR-015).
