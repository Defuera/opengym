# ADR-025: One Proposal Block for What the Coach Offers

## Status

Accepted (details Proposed)

The owner set the direction on 2026-11-19. His words: "It's important that we use the same architecture across the app and entities and reuse architecture blocks and UI. They can be configurable. AI can generate a session; AI can generate a program. AI can edit a session with no explicit user approval; AI can edit a program, explicit user approval required." And for chat: "the AI should be able to use 'tool calls' to act ... inside the chat the AI can make a proposal ... and button agree / cancel. We don't need to implement it now, but our data architecture and schema should allow it. Make sure that we are simplifying the system." He agreed to build the block first for Program and to leave the session start as it is for now.

## Date

2026-11-19

## Context

The AI writes or proposes through several separate mechanisms: start requests with a feedback chain, notes and goals written from chat, place notes with a trace table, the structure of the person's own text, and the computed views. A Program needs "the coach proposes, the person accepts". Copying the start request mechanism a second time, and a third time for chat, would add two more.

## Decision

- A Proposal is a value the coach (or rules code) offers for one thing the person owns. It is never a fact. A fact is written when the proposal is applied.
- One table `proposals`: the target (kind and, for a change, the id), the whole new value, a one-line reason, the target's version it was made on (`base`), the approval mode, where it was made (`origin`), the status, and what the person asked for.
- A change is the whole new value. No patch operations.
- Every target the coach may change has a number `rev` that the server raises on each write. A proposal made on an older `rev` becomes stale and is never merged.
- The approval mode comes from one policy map in server code, keyed by the target kind and the origin. The model cannot set it. Program: always explicit.
- The coach never proposes a delete. A logged session is never a target.
- One card in the app shows any proposal: what is proposed, the reason, the feedback box, and Agree / Cancel when approval is explicit.

## Planned, not built (the schema allows it)

- Session start moves onto the block when chat proposals are built; `startRequests` and its two app stores are then removed. A session proposal made at start or by feedback is applied at once; one made in chat asks Agree / Cancel.
- A thread says what it is about (`about`: a running session, a program, a place, a limit), replacing `threads.placeId`. A chat opened from a running session sends the session with each message, because the session lives on the phone.
- The chat reply becomes text plus optional proposals in one JSON answer. No provider tool API (ADR-005 holds).
- In a running session what is done stays; a proposal replaces only the sets and exercises with nothing done.
- The "notes and goals from chat" job folds into the chat reply. Notes stay silent; goals ask.

## Stays outside the block, on purpose

Place learning with its trace (ADR-021), the structure of the person's own text (ADR-018), the computed views (plans, predictions, reviews, dashboards), and the session on the phone with its outbox.

## Consequences

- The block pays off when three things use it (program, session, chat). Until the session start moves, two mechanisms exist side by side. That is accepted so that a working daily path is not refactored without a visible gain.
- A proposal that nobody applies is deleted after 7 days.

## Verified and not verified

Verified by reading code (2026-11-19): only `places` has `updatedAt` among the facts (`functions/schema.ts`); the active session is local to the phone (`apps/mobile/lib/store.dart`). Not verified: that the block fits the session start without change; it was checked on paper only.
