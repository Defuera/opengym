# ADR-007: Server-Driven Dynamic Home

## Status

Accepted

## Date

2026-11-16

## Context

The home screen answers "how am I doing?". It must be generated from the user's goals (requirement A02 in `docs/requirements.md`: dynamic home from goals). Source: DECISIONS.md, section "Architecture".

## Decision

- The app has a fixed set of module widgets.
- The server sends a spec per user. The spec lists which modules to show and in which order.
- The frame stays fixed: the title, the week/month toggle and the plus button.
- Code computes all numbers. The AI only picks modules and order ([ADR-002](002-facts-vs-ai-proposals.md)).

## Consequences

- Inferred, not verified: a new module needs an app release, because the module widgets are fixed in the app. A new order does not.
- Goal editing is basic today (DECISIONS.md, known gaps).
- Dashboard day windows use UTC days, because the server does not know the time zone.
