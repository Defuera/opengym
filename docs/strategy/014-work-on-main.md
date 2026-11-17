# ADR-014: Work on Main Directly, No Pull Requests for Now

## Status

Accepted

## Date

2026-11-17

## Context

[ADR-011](011-main-branch-and-web-deploy.md) said that nobody commits to `main` and that work lands through a pull request. The project has one owner and one agent at this time. The owner said on 2026-11-17: "I think we can skip PRs atm, work on main directly."

## Decision

- Work is committed to `main` directly. No branch and no pull request is needed for now.
- Commits still follow `docs/guides/commit-guide.md`.
- Before a push, run the checks for the part you touched (`flutter analyze` and `flutter test`; `npm run typecheck` and `npm test`). The GitHub workflow `quality.yml` still runs on `main` after the push.

## Consequences

- A push to `main` deploys the old web app (`apps/web`) to Vercel. This part of ADR-011 stands. A change outside `apps/web` does not change what that deploy serves.
- No review happens before a change lands. A failing check shows after the push, not before.
- The owner can bring pull requests back at any time, for example when a second person joins. A new ADR records that.
