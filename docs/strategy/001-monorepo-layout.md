# ADR-001: Monorepo Layout

## Status

Accepted

## Date

2026-11-16

## Context

The repo `Defuera/opengym` held only the old Next.js PWA with Convex. A new Flutter app, a standalone backend and a web prototype were added. All parts need one home. The Digital Workforce repo is the model for the layout.

## Decision

The repo is a monorepo with these top-level folders:

- `apps/mobile` — the Flutter app. This is the product going forward.
- `apps/web` — the old Next.js PWA with Convex, moved as-is from the repo root.
- `apps/prototype` — a one-page web prototype. It is the behaviour reference for the Flutter app.
- `backend/api` — the standalone TypeScript API with the AI engine ([ADR-006](006-standalone-backend.md)).
- `infra/` — deploy scripts.
- `docs/` — the API contract, guides, requirements, design notes and these ADRs.

Each part keeps its own dependencies and its own README. There is no shared root `package.json`.

The old web app keeps deploying to Vercel from `main`. The Vercel project must set Root Directory to `apps/web` ([ADR-011](011-main-branch-and-web-deploy.md)).

## Consequences

- Each part builds and tests on its own. CI uses path filters so a change to one part does not run the others.
- Paths in the web app config are now relative to `apps/web`.
- Agents must read the root `CLAUDE.md` first, then the `CLAUDE.md` of the part they touch.
