# ADR-016: Start or Log; the Vocabulary Comes From the Log

## Status

Accepted

## Date

2026-11-17

## Context

The owner tapped "Other activity" to get a quick home session from the coach. The app recorded an activity instead. He asked for two intents only, Start session and Log, each in a bottom sheet, with no fixed lists in the app: a kind of session he starts once must appear in the proposals the next time. He asked for a second opinion from the model `gpt-6-astra`; its review of the repo is the source of the limits below.

## Decision

- Home has two actions. **Start session**: the coach prepares a session with sets to follow. **Log**: the user records something already done. Each opens a bottom sheet with proposals and one free-text field.
- Code owns the shape of facts, validation, safety checks, idempotency and offline behaviour. The AI proposes names, order, focus, plan content and text. The app accepts a proposal and writes the fact (ADR-002 stays).
- `kind` on a session means the shape of the record: `gym` = a session with sets, `activity` = time and distance. A session with sets may have any activity name ("Gym", "Home"). This replaces the rule of ADR-013 that a session with sets is always "Gym".
- The app holds no fixed list of activities, foci or starter plans. Both lists come from the log. With no history and no AI answer, the fallback is an empty session with the typed name.
- A typed request is a proposal request, not a fact. The AI maps it to a name already in the log when one fits. The session keeps the name the user accepted.
  Update: the Start tab's "Other" step takes one free text, and the `build_session` coach job answers it (the earlier `interpret_request` job is removed). The coach names the activity and reuses a log name when it means the same.
- Known names are matched by a deterministic key (case and spacing). A stored vocabulary table with aliases is not added now; it comes when the user needs renames or merges, and only a user action may write it.
- The AI never sits in the tap path (ADR-003). Stored proposals open at once. Only "something new" waits for the AI, and the user can start empty without waiting.
- Plans are stored for the few most likely proposals, not for every known activity.
- An exercise the muscle table does not know is never treated as safe by an AI guess alone: a plan check that cannot decide falls on the careful side.

## Consequences

- ADR-013 is partly replaced: "Gym is one activity" stays true for the gym, but other activities may also have sets.
- Plans are keyed by activity and focus.
- The start screen and the fixed lists in `apps/mobile/lib/planner.dart` go away.
- A rename of `kind` to a clearer word is left for later; it is a wording change, not a behaviour change.
