# ADR-002: Facts Versus AI Proposals

## Status

Accepted

## Date

2026-11-16

## Context

The owner wants an AI engine behind a hard-coded input UI. The user must be able to trust the training log. Source: DECISIONS.md, section "Architecture" (the handover from the cloud chat workspace).

## Decision

Facts are sessions and sets. Only two things may write facts:

- the app, when the user logs a set;
- an import the user starts.

The AI never edits a fact. Everything the AI produces is a proposal. Each proposal carries `source: "ai"` or `source: "rules"`.

## Consequences

- A wrong AI answer cannot damage the log. The user can ignore a proposal.
- Dashboard numbers are always computed by code. The AI only picks modules and their order ([ADR-007](007-server-driven-home.md)).
- Code review must reject any code path where AI output writes a session or a set.
