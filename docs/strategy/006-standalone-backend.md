# ADR-006: Standalone Backend Instead of the Next.js and Convex App

## Status

Proposed

The owner has not confirmed this decision. DECISIONS.md labels it ASSUMED.

## Date

2026-11-16

## Context

The old web app already has a backend: Next.js API routes, in-memory repositories and a planned Convex migration. It also auto-deploys `main` to Vercel. The Flutter app needs an API and an AI engine. The owner's open question on "backend choice and schema" is still undecided.

## Decision

Build a new standalone backend in `backend/api`:

- Node 22, TypeScript, Hono, zod, better-sqlite3, vitest.
- Repositories are interfaces. SQLite is the first implementation.
- The backend does not build on the old Next.js app.

Reason given in DECISIONS.md: the old app uses in-memory repositories and auto-deploys `main` to Vercel.

## Consequences

- Convex, or another store, can replace SQLite later by writing a new repository implementation.
- The old app and the new backend run side by side until the old app is retired.
- The backend is single-user today. It uses one app token.
- If the owner picks a different backend, this ADR must be superseded.
