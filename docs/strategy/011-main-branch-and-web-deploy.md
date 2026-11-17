# ADR-011: Never Commit to Main; Main Deploys the Web App

## Status

Partly replaced by [ADR-014](014-work-on-main.md): the rule "nobody commits to `main` directly" no longer applies. The rest stands.

## Date

2026-11-16

## Context

Vercel deploys the old web app on every push to `main`. After the monorepo move ([ADR-001](001-monorepo-layout.md)) the app sits in `apps/web`. Source: DECISIONS.md, section "Repo and process"; the old root CLAUDE.md.

## Decision

- Nobody commits to `main` directly. Work happens on a branch and lands through a pull request.
- Commits follow `docs/guides/commit-guide.md`: conventional commits, lowercase, short.
- The Vercel project must set Root Directory to `apps/web`. Inferred, not verified: without it Vercel cannot find the Next.js app and the deploy fails.
- The Convex backend of the web app deploys separately. After a change in `apps/web/convex/`, run `npx convex deploy` from `apps/web`.

## Consequences

- A merge to `main` goes live for the web app.
- Changes to `apps/mobile`, `backend/api` and `docs/` do not change the web deploy, except through the Vercel root setting.
- The Vercel Root Directory change is a manual step in the Vercel dashboard. It is not verified here.
