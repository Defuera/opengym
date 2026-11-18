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
| [006](006-standalone-backend.md) | Standalone Backend Instead of the Next.js and Convex App | Hosting replaced by 012 |
| [007](007-server-driven-home.md) | Server-Driven Dynamic Home | Accepted |
| [008](008-flutter-app-structure.md) | Flutter App Structure and In-App Widget Gallery | Accepted |
| [009](009-cloud-run-hosting.md) | Backend Hosting on Cloud Run With SQLite on a Cloud Storage Volume | Replaced by 012 |
| [010](010-no-medical-wording.md) | No Medical Wording | Partly replaced by 015 |
| [011](011-main-branch-and-web-deploy.md) | Never Commit to Main; Main Deploys the Web App | Partly replaced by 014 |
| [012](012-convex-backend.md) | Hosted Convex Backend With Separate Commands and Read Models | Accepted |
| [013](013-activity-first-focus-is-advice.md) | Activity First, Focus Is Advice | Partly replaced by 016 |
| [014](014-work-on-main.md) | Work on Main Directly, No Pull Requests for Now | Accepted |
| [015](015-own-records-and-limits.md) | The User May Store Own Records; Limits Become Rules | Accepted |
| [016](016-start-or-log-vocabulary-from-the-log.md) | Start or Log; the Vocabulary Comes From the Log | Accepted |
| [017](017-log-entries.md) | Log Entries Are Free Notes With Attachments | Proposed |
| [018](018-log-by-text.md) | Log an Activity as One Text; the AI Fills the Structure | Proposed |
| [019](019-trackers-through-the-phone-health-store.md) | Trackers Through the Phone's Health Store | Proposed |
| [020](020-delete-marks-then-purges.md) | Delete Marks the Row, a Cron Erases It After 72 Hours | Accepted |
