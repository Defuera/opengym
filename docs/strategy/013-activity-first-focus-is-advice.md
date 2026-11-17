# ADR-013: Activity First, Focus Is Advice

## Status

Accepted

The owner decided this on 2026-11-17. The "Implementation choices" section below lists what the owner did not decide.

## Date

2026-11-17

## Context

Gym sessions stored their flavour in `type` ("Upper", "Legs", "Push", "Pull"). The start screen then listed one entry per flavour, as if "Gym upper" and "Gym legs" were different activities. The owner said:

> Gym upper / gym legs must not be separate activities. The activity is Gym, and the set of exercises is advised by the AI. Same for running: I just go for a run and the AI can advise the session type.

## Decision (the owner's)

- The activity is Gym. Upper, Legs, Push and so on are not activities.
- The AI advises which exercises to do. The same holds for running: one activity, and the AI may advise the session type.
- A session has `kind`, `type` (the activity: "Gym", "Run", "Bouldering"), and an optional `focus` (max 40 characters): the flavour of that session. For kind `gym`, `type` is always "Gym".
- `focus` is a label. The AI advises it and the user may override it. Once the session is saved it is a fact, written by the app like every other fact. The AI never writes sessions (ADR-002).
- Predictions rank activities. Gym appears at most once, with the advised focus.

## Implementation choices (not decided by the owner)

- **Focus chips.** The prepare and session screens show a row of chips with the known gym foci, the advised one first and marked. A pick swaps in the stored plan of that focus. It never calls the AI (ADR-003). The chips are hidden after the first set is done. A later change only renames the label.
- **Known foci.** The foci in the gym log. The starter foci (Push, Pull, Legs) are used only while the log has no gym focus. One plan is built per known focus. The app chips follow the same rule.
- **Advised focus, rules.** For Gym: the known focus done longest ago. After the AI answers, code replaces a gym focus that is not a known focus with the rules focus (ADR-004 validation). For other activities: the session type done longest ago, only if the log has one.
- **Run screen.** The advised session type is a text field the user can keep, change (text or chips of earlier ones) or clear.
- **Legacy normalisation.** Old rows and old app builds send a gym session as type "Upper" with no focus. Code reads that as type "Gym", focus "Upper" (backend `model/sessionShape.ts`, app `Session.fromJson`). A gym session that has a focus and another type is rejected.
- **Plans table.** Plans are keyed by `focus`. The old `type` key stays in the schema as optional until the migration has run. `focus` is optional in the schema for the same reason.
- **Migration.** `jobs/migrations:activityFirst` (an internal mutation, run by hand, once). See Consequences.
- **Reason text.** The Gym reason names the last gym session, for example "Last legs session was 2 days ago". The app shows it after the focus: "Upper · Last legs session was 2 days ago".

## Consequences

- The schema change deploys on its own. Old rows (type "Upper", no focus) still validate, because `focus` is optional and `type` is still a free string. Old `plans` rows (key `type`, no `focus`) validate because both fields are optional. Old `predictions` items validate because `focus` is optional. Until the migration runs, every read path normalises old rows, but plan lookups by focus find no stored plan for old rows. Plans are then computed by the rules planner until the next rebuild stores new ones.
- `jobs/migrations:activityFirst` takes `{}` (optional `batch`, `cursor`). It pages through sessions, sets `focus = old type` and `type = "Gym"` on gym rows, patches stored plans and predictions to the new shape, and then asks for one debounced rebuild. It is idempotent: a second run changes nothing and asks for no rebuild. Reviews (free text) and dashboards (layout specs) hold no gym type, so they stay as they are. If a rebuild stored a plan for a focus before the migration ran, the older legacy plan row is deleted as a duplicate.
- A later change can make `plans.focus` required and drop `plans.type` once the migration has run on the deployment.
- Reviews compare a session with the previous one of the same activity and focus.
- An older app build still works against the new backend: `commands/sessions:save` normalises its sessions, and `queries/plans:next` still accepts `type` as the old name of `focus`. The old build will show "Gym" for every gym session.

## Verified and not verified

Verified by running (2026-11-17): `npm run typecheck` and `npm test` in `backend/convex` (convex-test, in memory), including the migration run twice and in batches; `flutter analyze` and `flutter test` in `apps/mobile`.

Not verified: the migration against the real deployment (it was not run, by instruction); the schema deploy against real data (reasoned from the validators above, not run); the screens on a device or simulator (no UI run; only unit and one widget test); the AI answers with a real provider (only the mock and stubbed replies).
