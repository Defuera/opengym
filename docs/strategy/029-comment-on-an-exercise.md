# ADR-029: The Person Can Comment on an Exercise in a Session

## Status

Accepted (step 1 built; steps 2 and 3 Proposed)

Note: the owner asked for this in the session of 2026-11-22: "I want to be able to add comments to exercises. For example for bike I want to add photo with difficulty and heart rate and other stuff. For [another] exercise I want to mention that I feel my shoulder a bit." Two designs were written, one by the operator and one by the model `gpt-6-astra`, and one difference was settled between them (below). On showing the last comment the next time, the owner said: "No need to show last comment. It's momentary info, it's related to session, not to exercise itself".

## Date

2026-11-22

## Context

A finished session held one note for the whole session, and a time entry could hold a note. A sets exercise had no place for the person's words (verified by reading `backend/convex/functions/schema.ts` on 2026-11-22). The `note` on an exercise of the open session is the plan note of the coach, not the person's.

## Decision

- An exercise in a session gets one optional `comment`: the person's own words about how that exercise went that day, at most 1000 characters. The person can change or remove it.
- The comment lives on the exercise inside the session, in the open session and in the finished one. It is saved with the session in one write, through the existing outbox, so it works offline.
- The other design stored each comment as a linked log entry (`entries` with `sessionId` and `exerciseName`). It was dropped: a finished exercise has no id, so a link by name breaks when an exercise is in a session twice or is renamed; and entries have no outbox.
- The comment belongs to the session, not to the exercise in general. The app does not show an old comment when the exercise comes again.
- The comment is a fact in the person's words. In the open session only the app writes it, and an outside writer never replaces an exercise that has a comment (`mergePlan`).
- The coach reads it word for word, on the exercise it belongs to: in `recentSessions` of the session builder (the last 21 days), and in the review of that session.
- A comment about the body ("I feel my shoulder a bit") stays a comment. It never becomes a limit by itself.

## Proposed next steps (not built)

- Step 2: photos on the comment. Built as `commentFileIds` by ADR-043 (without an upload queue: photos need a connection).
- Step 3: an action "Make this a limit" on a comment; a job that reads a photo of a machine display and proposes numbers, which the person confirms before the app saves them (the AI never writes facts, ADR-002); voice.

## Consequences

- The coach can react to how an exercise felt, without the person opening the chat.
- A comment is not shown in the Log entries timeline.
- The session edit screen keeps a comment but does not let the person change it yet.
