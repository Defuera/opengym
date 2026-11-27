# ADR-042: The Coach Builds a Session That Fits the Person's Routine and Follows the Program Order

## Status

- Part 1 (time budget from the routine): Accepted. The owner reported the fault and asked for the fix in the session of 2026-11-27.
- Part 2 (program order): Proposed. The agent decided it as a coach-quality change. The owner has not confirmed it.

## Date

2026-11-27

## Context

The owner's words (2026-11-27): "by this point I should know that I go in the morning on weekdays, like for like an hour. And yesterday I generated a huge session ... it's not getting adapted to my routine."

Verified (live read of the owner's log on 2026-11-27): his weekday-morning sessions start between 08:17 and 08:45 and last 53, 75, 76, 71 and 103 minutes. The program session "gym legs" has 10 exercises as written.

Verified (read of the code before this change): the coach got `durationMin` for each recent session, but no computed routine. No sentence told it to fit a program session into the usual time.

Second fault, reported on the same day. The program week lists the sessions in order: A gym legs, C bike day with upper body, B squat and balance, D bike day. The owner tapped the activity "Gym" the day after A. The prompt said to take the session "that fits the chosen activity and is still open". The bike days have the activity "Cycling", so the coach skipped slot 2 and gave slot 3. The result was two knee days in a row. Inferred: this is the cause, from the prompt text and the order of the slots. No model trace was read.

## Decision

### 1. A time budget, computed by code, obeyed by the coach (Accepted)

- Code computes `usualSessionNow` (`functions/model/usualSession.ts`) and passes it in the `build_session` input, also on a rebuild after feedback.
- Source: the finished sessions done in the app (not imported) of the last 8 weeks, with a length of 10 to 240 minutes.
- The slot is the kind of day (weekday or weekend) times the part of day of now (morning before 12:00, afternoon before 17:00, else evening). The time zone is the one of the user (ADR-039): the start time of each session and `now` are read in that zone.
- Value: `{ when, sessions, usualMinutes (median length), usualSets (median number of sets) }`.
- With fewer than 3 sessions in the slot, all sessions of the same kind of day count and `when` says only "weekday" or "weekend". With fewer than 3 again, the fact is left out.
- Prompt: the budget is, in this order, a time the person names in the request, the note for today or the feedback; a time the person states in `notesFromTheUser` about their routine; else `usualSessionNow.usualMinutes`. `minutes` must not exceed it. When the program session does not fit, the coach keeps what matters most for the purpose of the program and the limits, cuts or shortens the rest, and says in `plan.rationale` in one short clause what it left out. The rule "the minutes are a promise" stays.
- No hard reject in code for the time. This is a prompt and a fact only. There is no wording safeguard (ADR-022).

### 2. The program order (Proposed)

- With a program, and a generic start (Gym, Strength, Cycling), the coach takes the first open slot of the week in the listed order, when the slot can be done at the current place. A bike day can be done at a gym.
- It names that session in `reason`, for example "Program order: Bike day 1 comes before B".
- It picks another session only when the request or the note asks for something else, or the chosen activity plainly cannot hold the slot (Swimming, Skiing, Yoga).
- When the note of the slot says other work can go there, the coach adds that work from `recentSessions` within the time budget.
- The program link needs no change. Verified (read of `programLinkFor` and a test): the link is found by the key the coach names and does not compare the activity, so `type` (the activity, exactly as given) can differ from the activity of the slot.

## Consequences

- Verified: the typecheck and the unit tests of the routine and of the link pass.
- Unverified: whether the model obeys the budget and the order. No live call was made. The owner tests this in the app.
- Bet (ADR-less rule of the working practices): the metric is the share of generated sessions whose planned `minutes` exceed the usual length of the slot by more than 20 percent, read from the live log. The value before is not measured. The read date is set after the owner has used the change for two weeks.

## Not decided

- Whether the budget should use the median or a higher percentile. The median is the builder's choice (inferred as the simplest; not confirmed by the owner).
