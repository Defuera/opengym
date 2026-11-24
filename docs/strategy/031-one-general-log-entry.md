# ADR-031: One General Log Entry, and the AI Says What It Is

## Status

Accepted (step 1 built; the next steps Proposed)

Note: the owner asked for this in the session of 2026-11-23, after a dinner photo went to the import route and was reported as "no training data": "There must be no specific routes for such things. What we need is a general log entry and then AI decides what this is: is it nutrition data, is it exercise log that needs to be imported, is it a limitation, whatever it is." He confirmed step 1 the same day: "Yeah, go ahead. You can ship it."

## Date

2026-11-23

## Context

The Log side had separate routes: a note, a completed activity as text, "Something new", and an import of a photo or a file. The person had to choose the route before the app knew what the input was (verified by reading `apps/mobile/lib/screens/log_sheet.dart` on 2026-11-23). A wrong choice gave a wrong result. The design was discussed with the model `gpt-6-astra`; its answer is a proposal, not the owner's decision.

## Decision

- The log entry (`entries`, ADR-017) is the one general input: the person's words, photos and files, stored unchanged.
- One job, `read_entry`, reads every new or changed entry and says what it is: `meal`, `training`, `body`, `goal` or `other`, with one line about it (at most 120 characters).
- The result is stored on the entry as `read: { status: "pending" | "ready" | "failed", rev, kind?, summary? }`. It is a label made by the AI, not a fact. The person's words and files never change.
- `rev` names the text and the file list that were read. A changed text or file list starts a new read. A late result for an older text is dropped. A change of the time alone keeps the label.
- The job follows the usual pipeline (ADR-004): prompt, provider, JSON, zod, one retry. No plain code can read a photo, so with no AI answer the status is `failed` and the entry shows as the person wrote it.
- Step 1 writes nothing else: no session, no goal, no note for the coach, no limit.
- The app shows the kind after the time of the entry ("Today, 20:05 · Meal"). For an entry with photos or files it also shows the one line, and "Reading…" while the job runs.
- The coach reads the one line for an entry with photos or files (`attachmentsShow` in `logEntriesFromTheUser`), so it knows what a photo showed after the 24 hours in which the photo itself is sent.

## Proposed next steps (not built, not confirmed by the owner)

- Built (backend, ADR-032): the log chat drafts sessions, goals, limits and notes; the person presses Done and plain code writes them, tagged with the entry. The result is a draft, not a write at once. Not built: the app screen, and the same for the old `read_entry` route.
- The old log and import routes on the Log side go away.
- Entries save offline through the outbox.
- The chat and the goal form use the same reader. (The chat is built: the log chat of ADR-032. The goal form is not.)

## Consequences

- Each entry costs one small AI call (up to 4 images).
- The Start session tab does not change (requirements, "Starting a session").
