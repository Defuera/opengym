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
| [015](015-own-records-and-limits.md) | The User May Store Own Records; Limits Become Rules | Accepted (one clause superseded by 033) |
| [016](016-start-or-log-vocabulary-from-the-log.md) | Start or Log; the Vocabulary Comes From the Log | Accepted |
| [017](017-log-entries.md) | Log Entries Are Free Notes With Attachments | Proposed |
| [018](018-log-by-text.md) | Log an Activity as One Text; the AI Fills the Structure | Proposed |
| [019](019-trackers-through-the-phone-health-store.md) | Trackers Through the Phone's Health Store | Proposed (three lines superseded by 036) |
| [020](020-delete-marks-then-purges.md) | Delete Marks the Row, a Cron Erases It After 72 Hours | Accepted |
| [021](021-places-the-coach-learns.md) | Places and Their Equipment Are Learned by the Coach | Accepted |
| [022](022-no-wording-safeguards-while-one-owner-tests.md) | No Wording Safeguards on the Coach While One Owner Tests | Accepted |
| [023](023-exercise-animation-from-two-key-poses.md) | Exercise Animation From Two Key Poses, Redrawn From Open Photos | Accepted (details Proposed) |
| [024](024-program-is-a-plan-for-a-period.md) | A Program Is the Person's Plan for a Period | Accepted (details Proposed) |
| [025](025-one-proposal-block.md) | One Proposal Block for What the Coach Offers | Accepted (details Proposed) |
| [026](026-talk-to-the-coach-in-one-chat.md) | Every Conversation With the Coach Is the Chat | Accepted (details Proposed) |
| [027](027-store-ai-calls-for-90-days.md) | The Server Stores Every AI Call for 90 Days | Accepted |
| [028](028-open-session-lives-on-the-server.md) | The Open Session Lives on the Server, With a Copy on the Phone | Accepted |
| [029](029-comment-on-an-exercise.md) | The Person Can Comment on an Exercise in a Session | Accepted (steps 2, 3 Proposed) |
| [030](030-program-is-data-for-the-coach.md) | A Program Is Data for the Coach | Accepted |
| [031](031-one-general-log-entry.md) | One General Log Entry, and the AI Says What It Is | Accepted (step 1 built; next steps Proposed) |
| [032](032-one-chat-with-functions.md) | One Chat With Functions | Accepted (steps A to G built; decisions after step A Proposed) |
| [033](033-coach-reads-records.md) | The Coach Reads the Person's Records | Accepted (supersedes one clause of 015) |
| [034](034-voice-wave-and-transcript-check.md) | Voice: a Live Wave, and the Transcript Goes to the Text Field | Accepted |
| [035](035-coach-can-change-session-place.md) | The Coach Can Change the Place of the Session, and a Rebuild Keeps It | Accepted (replaces one rule of 032) |
| [036](036-two-way-health-store-exchange.md) | Two-Way Exchange With the Phone's Health Store | Accepted |
| [037](037-chat-composer-always-works.md) | The Chat Composer Always Works; Messages Wait in the Outbox | Accepted (replaces one rule of 026 and 032) |
| [038](038-count-ai-usage.md) | Every Paid AI Call Is Counted, With a User Id | Accepted (one clause replaced by 039) |
| [039](039-tables-ready-for-more-users.md) | Every Table and Function Is Ready for More Than One User | Accepted |
| [040](040-one-reply-for-quick-messages.md) | One Reply for Quick Messages | Accepted |
| [041](041-coach-debrief-after-a-session.md) | The Coach Debrief After a Session: an Evaluation That Ends With a Question | Accepted |
| [042](042-session-fits-the-routine.md) | The Coach Reads the Routine From the Raw Session Times and Follows the Program Order | Time budget Rejected, program order Proposed |
