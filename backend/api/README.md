# OpenGym backend

Lives in `backend/api/`; run every command below from this directory. The contract is `../../docs/api-contract.md`.

Single-user backend for the OpenGym app. Implements `../../docs/api-contract.md` (v1). Hono + SQLite + zod, AI through plain `fetch` (Anthropic, OpenAI, DeepSeek) or a built-in mock.

## Setup in 5 steps

1. `npm install`
2. `cp .env.example .env`
3. Edit `.env`: set `AI_PROVIDER` (`anthropic`, `openai`, `deepseek`, `mock` or `none`), that provider's `*_API_KEY`, and its `*_MODEL` (a current model id from the provider's docs). Set `APP_TOKEN` to a secret of your choice. `mock` needs no key.
4. `npm run dev` (or `npm start`)
5. The server prints the LAN URLs (for example `http://192.168.1.20:8787`) and the token. Enter both in the phone app; phone and computer must be on the same network.

If the chosen provider's key or model is missing, the server exits with a message saying which variable to set. If `APP_TOKEN` is empty a random token is generated and printed on each start.

## Switching providers

Change `AI_PROVIDER` in `.env` and restart. `none` (or unset) turns AI off: every endpoint still works from the plain-code rules, chat answers with a fixed "not available" reply. `GET /v1/health` shows `provider` and `aiConfigured`. Base URLs can be overridden with `ANTHROPIC_BASE_URL`, `OPENAI_BASE_URL`, `DEEPSEEK_BASE_URL`.

## Tests

`npm test` (vitest, mock provider, temp database, stubbed fetch, no network). `npm run typecheck` for types. With a server running: `BASE_URL=http://localhost:8787 TOKEN=... scripts/smoke.sh`.

## What each AI job does

Every job asks for JSON only (except chat), validates it with zod, retries once, then uses a plain-code fallback. Logs show which path ran (`[ai] job=... path=ai|fallback`).

| Job | Does | Fallback |
|---|---|---|
| `plan_session` | Proposes the next session of a type from log, goals, active context. Code then caps 12 exercises, 10 sets, weight at 1.25x the heaviest logged. | Repeat last session of that type, else starter template |
| `predict_activity` | Ranks likely next sessions for the start screen | Rotation: longest-ago gym type, then frequent activities |
| `build_dashboard` | Picks dashboard modules and parameters; code computes every number | Fixed layout |
| `chat` | Coach reply in a thread (reads this thread, summaries of other threads, recent log, goals, active context, attached files) | Fixed "AI is not configured" reply |
| `extract_from_chat` | Turns "ankle felt tight after squats" into a context item, explicit wishes into goals | Nothing extracted |
| `summarise_thread` | Short thread summary other threads can read | Last user message, truncated |
| `review_session` | Summary of a finished session vs the previous one of that type | Set counts and top sets |
| `import_data` | Maps text chunks (12k chars, max 40 per file) or a photo to sessions/goals/context tagged with the import id | Nothing imported, job note says AI is required |

Plans, predictions and dashboard layouts are stored proposals. Writes (sessions, goals, context, imports, chat extraction) invalidate them and regenerate in the background. Only `GET /v1/plans/next` may call AI in the request (8 s budget, then rules).

## Known limits

- Single user, one shared token, no accounts.
- Audio files are stored but not transcribed.
- DeepSeek has no image input: image imports are skipped with a job note, image attachments in chat are noted to the coach as unreadable.
- PDFs are read with `pdf-parse`; scanned PDFs have no text and are stored only (a job note says so).
- Dashboard "days" and active-day counts use UTC calendar days.
- Background work runs in one in-process queue; pending tasks are lost on restart (proposals are then regenerated on the next write or served from rules).
- Data lives in `DB_PATH` (default `./data/opengym.db`), uploads in `./data/files`.

## Deploy to Google Cloud Run

Files: `Dockerfile`, `.dockerignore` (here) and `../../infra/deploy-cloud-run.sh` (not run by anyone yet; read it first). The script takes `GCP_PROJECT`, `BUCKET`, optional `GCP_REGION` (default `europe-west1`), `SERVICE` (default `opengym-api`), `GCLOUD_ACCOUNT`, `AI_PROVIDER`, `AI_MODEL`. Create the secrets `opengym-app-token` (APP_TOKEN) and `opengym-ai-key` (provider key) in Secret Manager first.

Env vars the service reads (names only): `APP_TOKEN`, `PORT`, `HOST`, `DB_PATH`, `SQLITE_JOURNAL_MODE`, `AI_PROVIDER`, `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, `ANTHROPIC_BASE_URL`, `OPENAI_API_KEY`, `OPENAI_MODEL`, `OPENAI_BASE_URL`, `DEEPSEEK_API_KEY`, `DEEPSEEK_MODEL`, `DEEPSEEK_BASE_URL`. Health check: `GET /v1/health` (no auth). Every other `/v1/*` route needs `Authorization: Bearer <APP_TOKEN>`.

Persistence plan: a Cloud Storage bucket mounted at `/data` (Cloud Run gen2, gcsfuse), `DB_PATH=/data/opengym.db`, uploads in `/data/files`, `--max-instances=1`, `SQLITE_JOURNAL_MODE=DELETE`.

- Verified locally: with `SQLITE_JOURNAL_MODE=DELETE` the database reports `journal_mode=delete` and `scripts/smoke.sh` passes against the mock provider. The default stays `WAL`.
- Inferred, not tested on Cloud Run: that WAL fails on gcsfuse (WAL needs shared memory and file locks; gcsfuse has no such support). That `DELETE` mode works reliably on gcsfuse is also unverified. gcsfuse writes a file back on close/sync, so a crash or instance stop mid-write could lose recent writes or corrupt the database. Back up the bucket (object versioning) before relying on it.
- Inferred: one instance only, because two instances writing the same SQLite file on gcsfuse would corrupt it. The in-process task queue also loses pending work on instance shutdown.
- The deploy uses `--allow-unauthenticated` (the app token is the only protection). Keep the token long and random.
