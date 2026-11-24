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
- One job, `read_entry`, reads every new or changed entry and gives it a category and one line about it (at most 120 characters). Updated 2026-11-24: the category is dynamic (see "Dynamic categories" below). It was a fixed list: `meal`, `training`, `body`, `goal`, `other`.
- The result is stored on the entry as `read: { status: "pending" | "ready" | "failed", rev, kind?, summary? }`. It is a label made by the AI, not a fact. The person's words and files never change.
- `rev` names the text and the file list that were read. A changed text or file list starts a new read. A late result for an older text is dropped. A change of the time alone keeps the label.
- The job follows the usual pipeline (ADR-004): prompt, provider, JSON, zod, one retry. No plain code can read a photo, so with no AI answer the status is `failed` and the entry shows as the person wrote it.
- Step 1 writes nothing else: no session, no goal, no note for the coach, no limit.
- The app shows the kind after the time of the entry ("Today, 20:05 · Meal"). For an entry with photos or files it also shows the one line, and "Reading…" while the job runs.
- The coach reads the one line for an entry with photos or files (`attachmentsShow` in `logEntriesFromTheUser`), so it knows what a photo showed after the 24 hours in which the photo itself is sent.

## Dynamic categories (2026-11-24)

The owner asked for a dynamic categorization of logs, shown in different colours (his words are in `requirements.md`).

- `kind` is now a short free label: one or two words, Title case, at most 24 characters ("Meal", "Sleep", "Walk"). The stored type is a string. Old rows keep `meal`, `training`, `body`, `goal` and `other`: they validate and show as "Meal", "Training", "Body" and "Goal". `other` shows no label, as before. No old entry needs a re-read.
- The AI gets `categoriesInUse` (the labels of the person's last 200 entries, most used first). It reuses one when it fits and creates a new one only when none fits. This applies to `read_entry` and to `draft_log` in the log chat.
- Plain code tidies the label (`model/entryCategory.ts`): trim, one space, cut at 24 characters, a case-insensitive match to a known label (the known spelling wins), else Title case. The fallback is `other`.
- No code branches on the category. A workout is known by `read.made.sessionId`, not by the label, so no separate flag was added.
- Colour (updated 2026-11-24). The first build had a fixed palette of 8 colours in the app, picked by a hash of the label. The owner asked: "did you hardcode colors?" Then he decided: "no need to hadcode colors either, just give to the agent a palette as a reference and they will do it themselves". So the AI picks the colour of a new category. The prompt of `read_entry` and of the log chat carries a short reference palette (example hex colours: mid-dark, saturated, readable on a white card, not black) as guidance only, and the existing categories with their stored colours. The AI is told to pick a colour that fits the meaning and is clearly different from those in use. The reference palette lives in backend code (`model/categoryColor.ts`). The app has no palette.
- The category is stored once in the table `entryCategories` (`key` = lower-cased label, `label`, `color`, `createdAt`, `source` "ai" or "rules"). A stored colour never changes by itself. Code only checks that the value is `#RRGGBB` and writes it in upper case. There is no contrast or distance check in code (implementation detail: a colour that is too close to another one or too light is a prompt matter, not code). Fallback in plain code, for no or an invalid AI colour and for old labels: the first reference colour not in use, else the palette in turn.
- Old labels get a stored colour with no AI call: `internal.jobs.migrations.categoryColors` (run by hand once after the deploy) and, from now on, the first time a label is written.
- The server sends the colour: `queries/entries:recent` joins it as `read.color`, and a log draft carries `color`. The app draws a row's border and label in that colour, or the ink border when there is none.

## Proposed next steps (not built, not confirmed by the owner)

- Built (backend, ADR-032): the log chat drafts sessions, goals, limits and notes; the person presses Done and plain code writes them, tagged with the entry. The result is a draft, not a write at once. Not built: the app screen, and the same for the old `read_entry` route.
- The old log and import routes on the Log side go away.
- Entries save offline through the outbox.
- The chat and the goal form use the same reader. (Built, ADR-032 step D: the goal form is gone; a goal is drafted in the chat.)

## Consequences

- Each entry costs one small AI call (up to 4 images).
- The Start session tab does not change (requirements, "Starting a session").
