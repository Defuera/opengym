# Architecture Decision Records

This directory holds the Architecture Decision Records (ADRs) for Gym Days (OpenGym). The format follows the Digital Workforce repo: Status, Date, Context, Decision, Consequences.

## Conventions

- Files are named `NNN-short-title.md`. Numbers never change and are never reused.
- Status is one of `Proposed`, `Accepted`, `Superseded`.
- `Proposed` means the owner has not confirmed the decision. The ADR says so in a note under the status.
- To change a decision, write a new ADR. Mark the old one `Superseded` and link the new one.
- Do not state facts or metrics that no source supports. Label inferences as inferred.
- Record every non-trivial decision here (see the root `CLAUDE.md`).

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [001](001-monorepo-layout.md) | Monorepo Layout | Accepted |
| [002](002-facts-vs-ai-proposals.md) | Facts Versus AI Proposals | Accepted |
| [003](003-ai-not-in-tap-path.md) | AI Is Never in the Tap Path | Accepted |
| [004](004-ai-job-pipeline-and-plan-limits.md) | AI Job Pipeline and Plan Safety Limits | Accepted |
| [005](005-interchangeable-ai-providers.md) | Interchangeable AI Providers via Plain Fetch | Accepted |
| [006](006-standalone-backend.md) | Standalone Backend Instead of the Next.js and Convex App | Proposed |
| [007](007-server-driven-home.md) | Server-Driven Dynamic Home | Accepted |
| [008](008-flutter-app-structure.md) | Flutter App Structure and In-App Widget Gallery | Accepted |
| [009](009-cloud-run-hosting.md) | Backend Hosting on Cloud Run With SQLite on a Cloud Storage Volume | Proposed |
| [010](010-no-medical-wording.md) | No Medical Wording | Accepted |
| [011](011-main-branch-and-web-deploy.md) | Never Commit to Main; Main Deploys the Web App | Accepted |
