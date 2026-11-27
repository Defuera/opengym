# ADR-042: The Coach Reads the Routine From the Raw Session Times and Follows the Program Order

## Status

- Part 1 (time budget from the routine): Rejected by the owner on 2026-11-27. See the decision.
- Part 2 (program order): Proposed. The agent decided it as a coach-quality change. The owner has not confirmed it.

## Date

2026-11-27

## Context

The owner's words (2026-11-27): "by this point I should know that I go in the morning on weekdays, like for like an hour. And yesterday I generated a huge session ... it's not getting adapted to my routine."

Verified (live read of the owner's log on 2026-11-27): his weekday-morning sessions start between 08:17 and 08:45 and last 53, 75, 76, 71 and 103 minutes. The program session "gym legs" has 10 exercises as written.

Verified (read of the code before this change): the coach got `durationMin` for each recent session, but no computed routine. No sentence told it to fit a program session into the usual time.

Second fault, reported on the same day. The program week lists the sessions in order: A gym legs, C bike day with upper body, B squat and balance, D bike day. The owner tapped the activity "Gym" the day after A. The prompt said to take the session "that fits the chosen activity and is still open". The bike days have the activity "Cycling", so the coach skipped slot 2 and gave slot 3. The result was two knee days in a row. Inferred: this is the cause, from the prompt text and the order of the slots. No model trace was read.

## Decision

### 1. The routine: the coach reads it from the raw data (Rejected: the time budget)

The first version computed a time budget in code (`usualSessionNow`: the median length of the sessions in the slot of weekday and part of day) and added a prompt rule to obey it. The owner rejected it on 2026-11-27. His words: "I don't like this solution. This is too specific. Code just needs to get information on my work hours. That's it. He needs to encourage himself with no additional prompts. You're trying to be kind of too detailed and too nudgy. It's not how it should work. AI can solve this."

Decision:

- The coach picture already gives, for each recent session, `date`, `start` (local time) and `durationMin`, and gives `timeNow` (`model/ai/jobs/coachPicture.ts`). That raw data is the whole solution. The coach reads the routine from it.
- There is no computed fact and no prompt rule about a time budget. The code `usualSession.ts`, its test and the `usualSessionNow` input field were removed.
- The rule "the minutes are a promise" stays as it was.
- Whether the model now fits the session to the routine is unverified. The owner tests this in the app.

### 2. The program order (Proposed)

- With a program, and a generic start (Gym, Strength, Cycling), the coach takes the first open slot of the week in the listed order, when the slot can be done at the current place. A bike day can be done at a gym.
- It names that session in `reason`, for example "Program order: Bike day 1 comes before B".
- It picks another session only when the request or the note asks for something else, or the chosen activity plainly cannot hold the slot (Swimming, Skiing, Yoga).
- When the note of the slot says other work can go there, the coach adds that work from `recentSessions`.
- The program link needs no change. Verified (read of `programLinkFor` and a test): the link is found by the key the coach names and does not compare the activity, so `type` (the activity, exactly as given) can differ from the activity of the slot.

## Consequences

- Verified: the typecheck and the unit tests pass after the removal.
- Unverified: whether the model obeys the program order and reads the routine well. No live call was made. The owner tests this in the app.
- Less code and a shorter prompt. The coach has no extra nudge about time.
