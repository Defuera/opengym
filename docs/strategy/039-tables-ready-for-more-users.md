# ADR-039: Every Table and Function Is Ready for More Than One User

## Status

Accepted

Note: the owner asked for this in the session of 2026-11-26 (words below). The design details (table decisions, index names, the two deploy points, the helper names) are the builder's and are not confirmed by the owner. Where this text says "inferred", no source or live check backs it.

## Date

2026-11-26

## Context

The owner said: "Yeah, I know that I'm the only one user today, but let's rework schema and database such that we're ready for multi-user. We will implement a login soon, and let's count tokens ..." Counting tokens is done (ADR-038). This ADR is the other part: phase B. Before it, one shared app token opened the whole database, and only `aiUsage` held a user id (the constant `"owner"` from `lib/currentUser.ts`). The reads took the first row of a table, or all rows of a table. The sessions, notes, files, chat and settings of a second person would have mixed with the owner's.

This is the Convex backend only (`backend/convex`). The Flutter app is not changed: it keeps sending the one app token, and the app never sees a user id.

## Decision

### The table `users`

`users { userId, createdAt, name?, timezone? }`, index `by_userId`. `userId` is the id the other tables use. The owner is the constant `"owner"` (`lib/currentUser.ts`, the same value `aiUsage` already used). `timezone` is an IANA name. No code makes a `users` row on its own yet: the login phase will. `jobs/migrations:ensureOwner` makes the row of the owner. A user with no row (the owner before the migration) works: the time zone falls back to the deployment's.

### Every table, one by one

"Per user" means: a required `userId: string` (see the two deploy points below) and indexes that start with `userId`, one for each way the table is read. The old indexes without `userId` are gone, except the ones named in the last column.

| Table | Decision | Why | Indexes (all start with `userId` unless noted) |
|---|---|---|---|
| `sessions` | per user | the log | `by_user_and_sessionId`, `_endedAt`, `_importId`, `_deletedAt`; kept global: `by_deletedAt` (purge) |
| `goals` | per user | | `by_user_and_goalId`, `_createdAt`, `_importId` |
| `context` | per user | | `by_user_and_itemId`, `_createdAt`, `_importId` |
| `entries` | per user | | `by_user_and_entryId`, `_at`, `_deletedAt`; kept global: `by_deletedAt` (purge) |
| `entryCategories` | per user | the label and colour of a category are the person's; the key is unique per user | `by_user_and_key` |
| `trackerDays` | per user | | `by_user_and_date` |
| `trackerWorkouts` | per user | | `by_user_and_workoutId`, `_startedAt` |
| `places` | per user | | `by_user_and_placeId` |
| `placeChanges` | per user | | `by_user_and_placeId` |
| `programs` | per user | | `by_user_and_programId`, `_deletedAt`; kept global: `by_deletedAt` (purge) |
| `proposals` | per user | | `by_user_and_proposalId`, `_createdAt`, `_threadId` |
| `limits` | per user | | `by_user_and_limitId` |
| `records` | per user | the person's own words (ADR-015) | `by_user_and_recordId`, `_limitId` |
| `checkins` | per user | | `by_user_and_checkinId`, `_limitId`, `_sessionId` |
| `imports` | per user | | `by_user_and_importId`, `_createdAt` |
| `threads` | per user | | `by_user_and_threadId`, `_updatedAt` |
| `messages` | per user | | `by_user_and_messageId`, `_threadId`, `_turnId` |
| `files` | per user | the owner of the blob (see "Files") | `by_user_and_fileId` |
| `plans` | per user | read model | `by_user_and_focus`, `by_user_and_activity` |
| `predictions` | per user | legacy read model, no code writes it any more | `by_user` |
| `dashboards` | per user | read model, one row per user and `days` | `by_user_and_days` |
| `reviews` | per user | read model | `by_user_and_sessionId` |
| `startRequests` | per user | | `by_user_and_requestId`, `_createdAt` |
| `aiCalls` | per user | the trace holds the prompt, so it holds the person's data | `by_user_and_at`, `by_user_and_job`; kept global: `by_at` (the 90-day purge) |
| `aiUsage` | per user (already, ADR-038) | | `by_user_and_at`; kept global: `by_at` (the operator report) |
| `openSession` | per user, ONE ROW PER USER | was `first()` | `by_user` |
| `settings` | per user, ONE ROW PER USER | was `first()`. The coach model is a choice of the person. The provider model list cache (`modelList`, `modelListError`) stays in the same per-user row: a judgement call. The list is the same for every user (inferred: one deployment key), but keeping it in the row costs one free `GET` per user and keeps the table simple. It could move to a shared table later | `by_user` |
| `rebuilds` | per user, ONE ROW PER USER | the debounce state of the rebuild; was `first()` | `by_user` |
| `users` | new | the people | `by_userId` |
| `exerciseArt` | SHARED, no `userId` | a catalogue of drawings, one per exercise name, made from the name and public photos; it holds no personal data (inferred: an exercise name a person typed is the only link to a person, and the name is the key anyone would type). One drawing serves everyone and the paid image call is made once | `by_key`, `by_updatedAt` |

The daily cap of new drawings (`EXERCISE_ART_DAILY_MAX`) is therefore for the whole deployment, not per user. The paid image call is counted for the user whose request started it (`aiUsage.userId`).

### The one place that knows the user

`lib/auth.ts:requireUser(ctx, token)` is `async` and returns the user id. It replaces `requireToken`. Today the app token (`APP_TOKEN`) is the owner. When the login arrives, only the body of this function changes (it will look the token up in the database; that is why it takes the context and is `async`). Every public query, mutation and action (all of `commands/` and `queries/`) starts with `const userId = await requireUser(ctx, token)` and uses `userId` for every read and write.

`APP_EXTRA_TOKENS` is for tests only: a JSON object `{"<token>": "<userId>"}` that maps more tokens to more users, so a test can act as a second user. It is not set in any real deployment and must not be set there (it would make those tokens full users). It cannot take over the app token (the app token is checked first), and an empty token or an empty user id is refused. This is not a backdoor in the shipped config: the variable is absent, and `tests/auth.test.ts` checks that a second token is refused without it. Anyone who can set an environment variable on the deployment can already set `APP_TOKEN` (inferred).

Internal queries, mutations and actions, scheduled jobs and the AI pipeline take `userId` as an explicit argument, never a global: `jobs/*` (all but `purge`, `pdfText`, the four functions of the shared art that touch only its table, and the rollout functions), `lib/*Db` helpers (the second argument is `userId`), `runAiJob(ctx, userId, ...)`, `providerFor(ctx, userId)`, `countedCall` (`meta.userId`), `aiCalls:save` and `aiUsage:record`. Every scheduled call passes the `userId` of the request that started it. `lib/currentUser.ts` now holds only the constant `OWNER_USER_ID`; `currentUserId()` is gone.

The only job that loops over users is the hourly purge (`jobs/purge:run`). It erases rows that were marked as deleted and old traces through global indexes, reads no content, and every follow-up read uses the `userId` of the marked row.

### Files, ids from the client, and "not found"

- A file belongs to a user through its `files` row. The row key is `(userId, fileId)`: two users may both have a file called `f1`. A blob is reached only through the row of the caller (`fileByFileId(ctx, userId, id)`). A file id of another user is "not found" (`files:get` returns `null`, a note that names it is refused with "no registered file", `files:remove` returns `false`).
- Every id that comes from the client (sessionId, threadId, messageId, goalId, itemId, limitId, recordId, checkinId, placeId, programId, proposalId, requestId, importId, entryId, turnId) is looked up by `(userId, id)`. A row of another user gives the same answer as no row: `null`, `false`, an empty list, or the existing "not found" `ConvexError`. Nothing says the row exists.
- Two users may use the same client ids. A write with an id that another user has makes a row of its own (the idempotent upserts are per user).
- The app never gets a user id: queries that returned stored rows as they are now drop `userId` (`withoutUserId`).

### Time zone

`model/timezone.ts:timezoneOf(user)` is the only code that reads `APP_TIMEZONE`: `users.timezone` when set, else the env value, else UTC. `lib/timezoneDb.ts:userTimezone(ctx, userId)` reads the user row. The day and clock helpers (`localDate`, `localTime`, `dayWithWeekday`, `trackerForPrompt`, `coachPicture`, `logForPrompt`, and the job input builders) take an optional last argument `timeZone`; the jobs and `queries/programs:list` pass the zone of the user. Nothing sets `users.timezone` yet (no command), so every user has the deployment's zone until the login phase.

### AI jobs

The picture of the person, the traces (`aiCalls`) and the usage (`aiUsage`) carry the user of the request. `queries/usage:summary` returns the numbers of the caller only; `npm run usage` (internal `report`) reads all users and splits them in `byUser`. The coach model chosen in Settings is read per user (`queries/settings:override { userId }`).

## Two deploy points

The live database has rows without `userId`. Convex refuses a deploy whose schema a stored row breaks. So the work ships in two steps. The commits are in this order in `main`.

**Deploy point 1** is the commit `feat(mu1): add owner migration and report` (`f49f501`) and everything before it. The schema has `userId` OPTIONAL on every per-user table, plus the new indexes and the `users` table. Every WRITE sets `userId` (through `requireUser`, or the `userId` argument of a job). Every READ is UNCHANGED: still not filtered, so the live app works with the old rows. The migration and the report are in this part:

- `jobs/migrations:assignOwner`, an internal action: makes the `users` row of the owner when missing, then walks every per-user table in pages (one mutation per page, 20 to 100 rows) and sets `userId: "owner"` on each row that has none. It returns `{ users, tables: { <table>: { read, assigned } } }`. Idempotent and resumable: a row that has a `userId` is not touched; a second run assigns 0 everywhere.
- `jobs/migrations:userIdReport`, an internal action: pages through every table and returns `{ ownerUser, tables: { <table>: { total, withoutUserId } }, withoutUserId }`. (The task asked for an internal query. A query cannot read a big table in one call, so the action loops over the internal query `userIdReportPage`.)

**Deploy point 2** is everything after that commit (the tip of `main`): every READ goes through an index that starts with `userId`; the one-row tables are read per user; `userId` is REQUIRED in the schema; `assignOwner` is removed (it cannot be tested or needed once the schema requires the field). Deploy point 2 only after `userIdReport` shows zero rows without `userId`. If a row has none, Convex refuses the deploy: that is the wanted safety net, but the report shows it first.

### Operator steps

All commands run from `backend/convex`. No secret appears in them.

1. Check out `f49f501` (deploy point 1) and deploy it: `npx convex deploy`. Choose a quiet moment: a job that was queued before the deploy has the old arguments and fails (a queued rebuild runner, a review, a coach turn). A coach turn that fails this way leaves its thread `thinking` until the person sends the message again (inferred from `commands/messages:send`, which runs the coach again after a failed reply; not tried live). A lost rebuild runner can leave `rebuilds.runnerScheduled` stuck on `true` until point 2, which reschedules a lost runner (see Risks).
2. Read the state: `npx convex run jobs/migrations:userIdReport '{}'`. Expect `withoutUserId` above 0 (the old rows) and `ownerUser: false`.
3. Run the migration: `npx convex run jobs/migrations:assignOwner '{}'`. It returns the count per table. Run it a second time: every `assigned` must be 0.
4. Read the report again: `npx convex run jobs/migrations:userIdReport '{}'`. Required: `withoutUserId: 0` and `ownerUser: true`. If not, do NOT deploy point 2: run step 3 again (writes made by the live app since point 1 carry `userId` already) and check again.
5. Check out the tip of `main` (deploy point 2) and deploy: `npx convex deploy`.
6. Optional one-off, after step 5: nothing in the schema needs a manual step. `npx convex run queries/usage:report '{}'` (or `npm run usage`) should show all old usage under the user `owner`.

The operator functions that took no user now take one. Run them as the owner: `commands/sessions:restoreSession '{"userId":"owner","sessionId":"..."}'`, `commands/entries:restoreEntry '{"userId":"owner","entryId":"..."}'`, `jobs/places:seed '{"userId":"owner"}'`, `jobs/openSession:replacePlan` (add `"userId":"owner"`), `jobs/migrations:categoryColors '{"userId":"owner"}'`, `jobs/migrations:activityFirst '{"userId":"owner"}'`.

## Tests that guard this

- `tests/userIdWrites.test.ts`: every table gets rows through the real functions, and every row has `userId` (deploy point 1).
- `tests/multiUserIsolation.test.ts`: two users with the same ids. Every public query returns only the caller's rows (no word of the other user, no `userId`); every mutation with an id of the other user answers "not found" and changes nothing; the stored prompts and job inputs of one user never hold a word of the other; the purge of one user's note keeps the file with the same id of the other; one row per user in `openSession`, `settings` and `rebuilds`; the usage summary splits by user.
- `tests/userGuard.test.ts`: a static scan of `functions/**/*.ts` (not `_generated`). It fails when a per-user table is read without a `by_user…` index on `userId`, when a public function does not call `requireUser` and use the user, when an internal function takes no `userId`, when the owner constant or `APP_TIMEZONE` is used outside its one place, or when an insert names no user. The allow-lists are small and each entry has a reason (purge, the rollout report, the operator usage report, the shared art, three public functions that read no row).
- `tests/auth.test.ts`, `tests/userIdReport.test.ts`, `tests/userTimezone.test.ts`, `tests/rebuildLost.test.ts`.

## What is NOT done

- The login itself. There is still one app token and one real user (`"owner"`).
- Per-user provider keys or quotas. One deployment key serves every user. A usage limit per user is not built.
- Deleting a user and all their data, and exporting it. The tables are ready for it (every row has `userId`), but no function does it. The files (blobs) of a user would need to be deleted with their rows.
- A retention rule for `aiUsage` per user (ADR-038 left this open).
- A command that sets `users.timezone`, and a `users` row for any user but the owner.
- A check that a `storageId` sent to `commands/files:register` is not already used by a file of another user (see Risks).
- The old `apps/web` and `backend/api` are outside this change.

## Risks and open points

- **Rows with no `userId` at point 2.** Convex refuses the deploy (safe), but only if the report was not checked. Step 4 is required.
- **Jobs queued across deploy point 1.** A scheduled function that was queued under the old arguments fails on the new code. Short jobs only (a coach turn, a review, a rebuild runner). If a rebuild runner is lost the flag `rebuilds.runnerScheduled` stays `true`; since the last commit `markFactsChanged` treats a flag older than the debounce plus the max wait (35 s) as lost and schedules a new runner. Before point 2 that guard does not exist: deploy point 1 when the app has had no write for a minute (inferred: the window is 5 to 30 s).
- **A static guard is a text check, not a proof.** It finds the usual slip (a new read with no user index). It cannot see a read made through a helper that forgets the user. The two-user tests are the real check, and they only cover the functions they call.
- **`storageId` in `files:register`.** The app sends a `storageId` from its own upload. The code checks that the blob exists, not who uploaded it. A user who knew another user's `storageId` could register it as their own file. Storage ids are never returned to the app (queries return a URL only), and they are not guessable (inferred), so no way to learn one is known. A check would need an index on `files.storageId`. Not built.
- **`APP_EXTRA_TOKENS`.** Do not set it in production. Test-only (see above).
- **Shared art cap.** One user can use up the daily cap of new drawings for everyone.
- **The static `"owner"` mapping.** Until the login, a second person with the app token is the owner. The data is separated, the access is not.
- **Cost of the model list.** Each user's first `refreshModels` makes its own `GET` (free).
