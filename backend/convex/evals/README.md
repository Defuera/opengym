# Evals for the AI coach

This folder measures the coach with fixed cases. Design: `docs/evals-design.md`. This is build step 1: about 30 cases for the known complaints, with gates, run on the real jobs.

The code calls the real job code: `coachPicture`, `buildStartInput`, the job `build`, `runJob`, `finalizeStartProposal` and the other steps the server runs after the AI answers. It builds all input in memory. It never imports the Convex server runtime and never touches a database. `npm test` never calls a provider.

## Run a live pass

Set the same env names the server uses. Then run:

```
cd backend/convex
AI_PROVIDER=openai OPENAI_API_KEY=... OPENAI_MODEL=... npm run eval
```

Names: `AI_PROVIDER` (`anthropic`, `openai`, `deepseek`, `mock`), `<PROVIDER>_API_KEY`, `<PROVIDER>_MODEL`. `EVAL_PROVIDER` replaces `AI_PROVIDER`. `EVAL_MODEL` replaces the model. The runner reads only the process env. It reads no file. To load a `.env` file yourself, use `npx tsx --env-file=<file> evals/runner/main.ts`.

Flags (after `--`):

- `--samples N`: answers per case. Default 1.
- `--job NAME`: `build_session`, `chat` (the coach turn on a plain chat; only its message is judged), `parse_log` or `learn_place`.
- `--case ID`: one case.
- `--concurrency N`: cases at the same time. Default 4.
- `--max-calls N`: a hard cap on provider calls, retries included. Default 150. When it is spent, the run stops and the rest is marked `skipped` or `aborted`.
- `--timeout MS`: time budget of one job call. Default 35000, the same as the server.
- `--out DIR`: report folder. Default `evals/reports`.

Optional: `EVAL_PRICE_IN` and `EVAL_PRICE_OUT` (USD per million tokens) add a cost line. Without them the cost is `n/a`. Tokens come from the `usage` field of the provider answer.

`AI_PROVIDER=mock npm run eval` runs the whole set with no key and no network. The mock fails many cases on purpose: it is a smoke test of the runner.

## What you get

`reports/<timestamp>-<model>.json` has every case: the input, every raw answer, the final output, each check with pass or fail and the reason, time and tokens. `reports/<timestamp>-<model>.md` has the summary. Reports are not committed.

The exit code is 1 when a finished case failed a gate, 2 on a setup error.

## What the numbers mean

- **Gate pass %**: share of runs where every gate held. Gates are checks by code. Release needs 100.
- **Task success %**: share of runs where the gates held and every `expect` check held.
- **Fallback %**: share of runs where the plain code answered because the model failed twice or timed out. Such a run also fails the gate `model_answered`.
- **Retry %**: share of runs where a call was repeated (the first answer was invalid).
- **avg ms, tokens, cost**: per run, from the provider adapter.

Runs that did not finish (`error`, `aborted`, `skipped`) stay out of the rates. They are counted on their own line.

Every case also gets two gates by default. `valid_output`: the final output has the right shape. `model_answered`: no call ended on the fallback.

A check marked `warn` never fails a case. It shows in the report. The chat repetition check by token overlap is a warning.

## Layout

- `fixtures/`: invented personas (Mara, Jonas, Nia) with sessions, goals, limits, notes and places. A place has `text` (what the coach reads) and `has` / `lacks` keyword lists (what the checks use).
- `cases/`: the cases, as data, per job.
- `assertions/`: the generic checks and the evaluator.
- `runner/`: the pipelines per job, the provider wrapper, the budget, the CLI.
- `reporting/`: the JSON and Markdown writers. (`reports/` holds only their output.)

## Add a case

1. Pick a persona in `fixtures/`, or add one. Keep it invented.
2. Add an object to the right file in `cases/`. Give it an `id`, `family`, `about`, `persona`, the input pieces, `gates` and `expect`.
3. Write checks from the kinds in `types.ts` (`contains`, `notContains`, `count`, `minutes`, `equals`, `noAvoided`, `equipment`, and so on). A keyword matches a whole word. Use `{ re: "..." }` for a regular expression.
4. Run `npx vitest run tests/evals`. A test checks that the case is well formed.

A new kind of check needs code in `assertions/` and a line in `KINDS_BY_JOB`, plus a test with a good and a bad sample.

## Limits of step 1

The chat user is scripted: the messages do not react to the coach. There is no judge, no repeated-answer statistics and no held-back part yet. A gate on the size of a plan only means something when the model gives `minutes`: the server cuts the plan only then.
