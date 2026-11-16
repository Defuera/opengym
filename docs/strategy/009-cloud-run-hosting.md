# ADR-009: Backend Hosting on Cloud Run With SQLite on a Cloud Storage Volume

## Status

Proposed

The owner has not confirmed this decision. No source document records it. It comes from the monorepo restructure and is not yet deployed.

## Date

2026-11-16

## Context

`backend/api` stores data in a SQLite file ([ADR-006](006-standalone-backend.md)). The DW repo runs on Google Cloud Run and records that choice in its own ADRs. The deploy scripts live in `infra/`.

## Decision

- Deploy `backend/api` as a Cloud Run service.
- Mount a Cloud Storage bucket as a volume. The SQLite file lives there.
- Run a single instance only (max instances = 1).

## Consequences

- Inferred, not verified: SQLite does not allow safe concurrent writers across instances. A single instance avoids that.
- Inferred, not verified: a Cloud Storage volume is not a local disk. Write speed and file locking may differ. Test this before relying on it.
- Inferred: the single instance caps throughput. This suits a single-user backend.
- If load grows, move to a hosted database through the repository interfaces.
