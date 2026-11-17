# ADR-004: AI Job Pipeline and Plan Safety Limits

## Status

Accepted

## Date

2026-11-16

## Context

AI output can be malformed or unreasonable. The owner asked for a defined list of AI functions and a very strict data schema. Source: DECISIONS.md, section "Architecture"; `docs/api-contract.md`.

## Decision

Every AI job follows one pipeline:

1. Build the prompt.
2. Call the provider.
3. Parse the JSON.
4. Validate it with zod.
5. On failure, retry once.
6. If it still fails, use a plain code fallback.

Plan safety limits apply to every proposed plan:

- at most 12 exercises;
- at most 10 sets per exercise;
- planned weight is at most 1.25 times the heaviest logged weight for that exercise.

Code enforces these limits after validation. The backend README states that the code caps the plan.

## Consequences

- A bad AI answer produces the fallback, not an error for the user.
- Logs show which path ran: `[ai] job=... path=ai|fallback`.
- A new AI job must define its zod schema and its fallback before it ships.
