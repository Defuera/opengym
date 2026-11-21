# ADR-027: The Server Stores Every AI Call for 90 Days

## Status

Accepted

Note: the owner decided this in the session of 2026-11-21. To the question "Step 1 stores your coach inputs on the server. I propose we keep them for 30 days. Do you agree?" his words were: "let's keep for 90 for now".

## Date

2026-11-21

## Context

The goal is that the coach gives a high-quality answer for every input we send it, and that we can measure that quality. The method with the best record is to read real answers, mark what is wrong in each, and count the kinds of fault.

The server kept no trace of an AI call (verified by reading `backend/convex/functions/schema.ts` on 2026-11-21). It stored the result of a job, not the prompt that was sent, and not a first answer that the checks rejected. So nobody could see why the coach gave a bad answer.

## Decision

- Every AI job run that reaches the provider is stored as one row in the table `aiCalls`: the time, the job name, the provider and the model, the exact system text and messages that were sent, the number of images, every attempt (the raw reply, or the error and the reason a check rejected it, and its duration), the outcome (`ai` or `fallback`, with the fallback reason) and the total duration.
- Images are counted, not stored.
- A row is erased 90 days after the call, by the hourly purge (`jobs/purge:run`).
- The store step never fails a job: when the row cannot be written, the job result is used as normal and a warning is logged.
- No app screen and no query for the app reads this table. The operator reads it with `npx convex data aiCalls`.

## Consequences

- The table holds the owner's training data and notes for 90 days, in the same Convex deployment as the facts they come from. The user's own records still never go to an AI provider (ADR-015), so they are not in these rows either.
- A long text is cut at 200,000 characters so that a row stays under the document limit of Convex.
- Before a second person uses the app, this must be decided again: whose calls are stored, for how long, and who may read them.
