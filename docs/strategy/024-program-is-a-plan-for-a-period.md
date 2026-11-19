# ADR-024: A Program Is the Person's Plan for a Period

## Status

Accepted (details Proposed)

The owner asked for a Program entity on 2026-11-19 and said "let go" to step 1 as described to him. The section "Choices the owner has not confirmed" lists what he did not decide himself.

## Date

2026-11-19

## Context

The owner prepares a knee for a ski trip with a written 30-day plan: named sessions, a week pattern, changes by week, load rules and exit tests. The app could not hold it. He pasted "Session A" as a free text each time. The app had no memory of the week, of which session is next, or of the rules.

The design was made in two rounds with a second model (`gpt-6-astra`) as reviewer. The reviewer's main corrections are named below.

## Decision

- A Program is a fact the person owns: title, purpose, start and end date, a week pattern (the session keys of one week, in order), phases (week ranges, each with its sessions written out in full), rules as text, tests as text.
- The coach may generate a program and may propose a change to it. Nothing becomes active or changes without the person's "Agree" (see ADR-025).
- Code, not the AI, knows the week (from the dates, in the app's time zone), the phase and the next session (the first slot of this program week with no logged session).
- A program session is built by code: the session as written for the current phase, with the kg of the last session of the same kind. It does not pass through `build_session`. Reason (the reviewer read `model/startSave.ts`): the generic path caps, drops and shortens a plan, so it cannot promise the written session.
- A logged session stores `programId`, `programWeek`, `programSlot`, `programKey`. Done and missed are computed from these. The slot index tells two "A" sessions of one week apart (the reviewer's correction).
- Several programs may be active. Each is one row in the start sheet. Days outside a program work as before.
- The rules of a program are text in step 1. Nothing applies them.

## Choices the owner has not confirmed

- The week follows the calendar, not the work done.
- Goals get no date; the program holds the dates.
- The person may give feedback on a program session; the coach then rebuilds it like any session.
- One table with embedded phases and sessions. No events table, no rule engine in code, no version history of a program (the reviewer proposed these; left out as too much for one user).
- A program has at most 26 weeks, 8 phases, 8 sessions per phase.

## Consequences

- New tables `programs` and `proposals`; four optional fields on `sessions`. All additive.
- The AI job `build_program` has no code fallback: a failed job gives a failed proposal.
- Later steps: a morning question after a program session, week ticks, the tests check list, the coach proposing a change from the morning answers, a program summary in the coach's picture for normal sessions.

## Verified and not verified

Verified by running (2026-11-19): `npx tsc -p functions --noEmit`, `npx tsc -p evals --noEmit` and `npm test` in `backend/convex` (460 tests pass); `flutter analyze` and `flutter test` in `apps/mobile` (470 tests pass). One live run of `build_program` on the deployment with the owner's written knee program (3626 characters): the proposal was ready after 135 s with 5 phases, the sessions, 8 rules and 6 tests; the proposal was then declined.

Two findings of the live runs changed the code: the coach writes an exercise in a short form (`{sets: 3, reps: 10, kg}`) because one object per set was too long to write inside the time limit; and a phase may leave a session of the week out, because the coach made a last short phase without "Session B".

Not verified: the screens on a phone; accept, the start sheet row, a program session and its link against the real server; a change of an active program; feedback on a program session.
