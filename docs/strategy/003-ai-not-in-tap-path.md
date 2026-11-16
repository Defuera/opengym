# ADR-003: AI Is Never in the Tap Path

## Status

Accepted

## Date

2026-11-16

## Context

The user logs sets in the gym. Requirements ask for no extended typing and for one or two taps per action. Logging must also work with no network. Source: DECISIONS.md, section "Architecture"; REQUIREMENTS.md (convenient logging, no form-filling).

## Decision

- Logging is local and offline-first. The app saves to the phone first and syncs later.
- No tap waits for an AI call.
- The backend precomputes AI output after writes.
- The one exception is `GET /v1/plans/next`. It may call the AI in the request, with an 8 second budget. After that it falls back to rules.
- Plain code, not AI, does these jobs: pre-filling sets, ordering predictions when AI is off, and all stats.

## Consequences

- The gym loop works with the AI off, with a slow AI and with no network.
- Pending background AI tasks are lost if the backend restarts. DECISIONS.md lists this as a known gap.
