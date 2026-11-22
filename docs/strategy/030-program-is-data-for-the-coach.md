# ADR-030: A Program Is Data for the Coach, Not a Separate Start

## Status

Accepted

## Date

2026-11-22

## Context

ADR-024 gave a running program its own row in the start sheet. A tap on it started the next program session, built by code as written, without the coach. The other rows ("Gym", "Run") asked the coach, and the coach did not know that a program existed.

The owner, on 2026-11-22: "When I'm pressing plus, then I'm getting gym, and then I'm getting also, as far as I understand, it's like program widget. It really confuses me. [...] I always want to follow program regarding where I'm doing it. So I don't think we should have separate program entry point. [...] Program is just data for AI to generate sessions."

Verified on the same day by reading `model/startInput.ts` and `model/ai/jobs/coachPicture.ts`: the input of `build_session` held no program. In 19 test runs on the owner's real log the coach never used his active program.

## Decision

- The start sheet has no program row. A session starts from an activity, a free text, or empty, as before ADR-024.
- `build_session` gets `programsThePersonFollows`: every active program that runs today, with the week, the phase of that week, the slots of the week with done or not, the sessions as written for the phase, the rules and the tests (`model/programForCoach.ts`, plain code).
- The prompt says: the program comes before the coach's own ideas, and the person follows it wherever they train. The coach takes the open session of the week that fits the chosen activity, keeps its exercises, order, sets and reps, sets the weights, and changes only what today asks for, saying what and why.
- The coach names the program session it built (`program: {programId, key}`). Code finds the week and the first open slot with that key and stores the link on the proposal; the app writes it on the session. A link the code cannot place is dropped: the session is then a plain one.
- The Program screen stays under About me: the person reads the program there, pauses it, ends it, and talks to the coach about it.

## What this replaces in ADR-024

- "A program session is built by code. It does not pass through `build_session`." Replaced: it passes through `build_session`.
- "Each [active program] is one row in the start sheet." Removed.
- "The rules of a program are text. Nothing applies them." Now the coach reads them.

The reason ADR-024 gave still holds as a risk: the checks after the coach answers (`model/startSave.ts`) may cap or shorten a plan, so the written session is not promised word for word.

## Not verified

- A program session on a phone against the real server, with the link stored on the finished session.
- A bike day of a program. "Cycling" is logged through the log form, not through `build_session`, so that session gets no program link and its slot stays open. The prompt tells the coach to count work it sees in the recent sessions as done.

## Verified

One run of 7 requests on the owner's real log and real program with `gpt-6.2-sol` (2026-11-22): every plan named a program session; "Gym" with no note gave "B — Squat and balance" of week 1 with the written exercises, and named each exercise it replaced for missing equipment.
