# ADR-020: Delete Marks the Row, a Cron Erases It After 72 Hours

## Status

Accepted

Note: the owner asked for exactly this: "I want to be able to delete a session, make sure to 1. have a confirmation dialog 2. only mark as to delete on the server 3. delete stuff only after a 72 hours with a cron".

## Date

2026-11-18

## Context

Deleting a session or a note erased the row at once (and the review, or the files). A mistaken tap could not be undone. An offline phone could also resend an old write after the delete.

## Decision

- The app asks for confirmation in a closable sheet before it removes a session or a note. The sheet says the item leaves the log now and is erased for good after 72 hours.
- On the server, `remove` only sets `deletedAt` on the `sessions` or `entries` row. The review and the files stay.
- A marked row is invisible to every read (queries, jobs, coach, chat, dashboards, plans, reviews, load levels, imports). One helper per table in `lib/db.ts` does the filter, so a new read cannot forget it.
- A late `save` or `logText` for a marked id changes nothing. A pending parse or review result for it is dropped.
- An hourly cron (`jobs/purge:run`) erases rows marked more than 72 hours ago (`DELETE_AFTER_MS`), with the review of a session and the file rows and blobs of a note.
- The operator can restore a row within 72 hours with `restoreSession` or `restoreEntry` (`npx convex run`). There is no trash screen in the app.

## Consequences

- Storage keeps a deleted row for up to 73 hours.
- A user cannot restore by himself; the operator does it on request.
- Two rows never share an id: a marked row still holds its `sessionId` or `entryId` until the purge.
- Removing an import (`commands/imports:remove`) still erases its rows at once, marked or not.
