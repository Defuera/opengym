# ADR-038: Every Paid AI Call Is Counted, With a User Id

## Status

Accepted

Note: the owner asked for this in the session of 2026-11-26, with the words quoted in `docs/requirements.md` ("let's count tokens so we can evaluate approximately how much it will cost us to run this app and for how much should we sell subscription"). The details below (field choices, the formulas) are the builder's and are not confirmed by the owner.

## Date

2026-11-26

## Context

No token number was kept anywhere (verified by reading `backend/convex/functions/schema.ts` and the providers on 2026-11-26). The owner wants the cost of running the app, to price a subscription. The app has one user today and gets a login soon, so a usage row must carry a user id from the start.

## Decision

- A new table `aiUsage` holds one small row per provider attempt: `at`, `userId`, `job`, `kind` (`chat`, `transcribe`, `image`), `provider`, `model`, the numbers the provider reported (`inputTokens`, `cachedInputTokens`, `outputTokens`, `reasoningTokens`, `audioSeconds`, `audioBytes`, `images`, `imageSpec`, `inputImages`), `ms`, `ok` and `ref`. A retry is a second row. A number the provider did not report is absent, never 0. The row holds no prompt text, so the 90-day purge of `aiCalls` (ADR-027) does not touch it. Indexes: `by_at`, `by_user_and_at`.
- `aiCalls` rows get the summed `inputTokens`, `cachedInputTokens`, `outputTokens` and `reasoningTokens` of their attempts, so a trace shows its own cost.
- `ok` means the attempt gave a valid job result. A reply that the checks rejected is `ok: false` but still carries its tokens, because it was billed.
- `inputTokens` includes the cached tokens (the OpenAI convention). For Anthropic the code adds `cache_read_input_tokens` and `cache_creation_input_tokens` to `input_tokens`; cache writes are then priced like normal input (inferred: Anthropic bills them higher; the app sends no cache control today, so none appear).
- Providers report usage through an optional `onUsage` hook (chat: on the request; speech and image: a trailing options argument). The hook is called as soon as the answer is read, also when the reply is then found empty. `complete`, `transcribe` and `image` still return what they returned before.
- One function, `functions/lib/currentUser.ts:currentUserId`, gives the user id of every usage write. It returns the constant `"owner"` today. The multi-user phase replaces its body. No other table gets a user id in this step.
- Prices are data: `functions/model/aiPrices.ts` holds a map from kind and model id to dollars. It is empty, because no price is in the repo. `costOf(row, prices)` returns `undefined` when the model or a needed price is unknown.
- `queries/usage:summary` (token-checked) and the operator call `npm run usage` (internal `queries/usage:report`, no token) return totals, per day, per job, per model, per user, failed attempts, and per-user figures per active day and per 30 days. The formulas are in the doc comment of `queries/usage.ts`. A read is capped at 8000 rows and 366 days.

## What is counted, and what is not

- Counted: every chat or JSON completion made through `runAiJob` (all AI jobs), every speech-to-text call (`lib/transcribe.ts`), every image call of the exercise art (`jobs/exerciseArt.ts`, each redraw is its own row).
- Not counted: the model list call (`listModels`; it is a free `GET`). The eval runner (`backend/convex/evals`) calls `runJob` without a database; it keeps its own token numbers in its report. The old `apps/web` and `backend/api` apps are outside this backend.
- A request that failed before an answer (HTTP error, timeout) has no usage numbers. It is a row with `ok: false`. A timeout may still have been billed; the code cannot see that.
- Speech to text: gpt-4o-transcribe style answers give tokens, whisper style answers give seconds; the row keeps what came. The audio length is not computed from the file (not cheap to know); `audioBytes` is stored. Input audio tokens are not split from text tokens (inferred: the provider bills them at different rates; the row has one number).
- Field names read from the answers follow the providers' public API shapes as the builder knows them; no live call was made. Tests use stubbed answers.

## Consequences

- The usage rows are kept without a limit. They are small numbers, no prompt text. Before a second person uses the app, decide how long to keep them per user.
- Dollar figures stay absent until someone fills `aiPrices.ts` from the provider price pages.
- Day figures use UTC days.
