# ADR-018: Log an Activity as One Text; the AI Fills the Structure

## Status

Proposed

Note: the owner asked for this change in a message about the Log form. He has not confirmed this written decision.

## Date

2026-11-18

## Context

The Log form of an activity had a minutes stepper, a distance field, a session type with chips, a note and a button. The owner looked at it and said: remove everything, keep one text input, and the AI parses it into our schema. He also set a standing rule: an exercise reported without reps and weights means the usual reps and weights.

## Decision

- A done activity is logged as one text. The form holds the activity name and one multi-line field of up to 1000 characters.
- The text is the fact. The app saves the session at once with the text word for word in `note` (`commands/sessions:logText`). It does not wait for the AI, and it works offline through the outbox.
- An AI job, `parse_log`, then fills the structure of that same session from the text: `minutes`, `distanceKm`, a short `focus`, the day (when the text says one), and `exercises` when the text describes work with sets (then `kind` becomes `gym`; work in time inside such a session is a time exercise). This is the same pattern as goals (`parse_goal`).
- The job never changes `note`, `type` or `source`. It adds no number the text does not give.
- Reported without sets means the usual sets from the log: an exercise named without reps and weights gets the sets of the last time it was logged. Plain code does this, not the AI. An exercise that is not in the log and has no sets stays in the note only.
- `parse` on the session is `pending`, `done` or `failed`. The app shows one quiet line while it is `pending`.
- The user corrects the result in Edit. An edit clears `parse`, and a result that arrives later is dropped. A user save never writes `parse`.
- The job follows ADR-004. If the AI fails, plain code reads minutes and kilometres with a regex. `parse` is `failed` only when nothing was read.

## Consequences

- This narrows ADR-002. The AI still never creates a session by itself: the app writes the session. The AI now fills the structure of a fact from the user's own text, and only for a session the user just logged.
- A wrong reading is visible in the recap and easy to fix in Edit. The text stays as written.
- A session is briefly a plain text with no minutes. Lists show it without a length until the job has written.
- Open: a day word such as "last Monday" depends on the AI reading the weekday; the time zone is the owner's (`APP_TIMEZONE`).
