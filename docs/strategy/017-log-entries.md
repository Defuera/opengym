# ADR-017: Log Entries Are Free Notes With Attachments

## Status

Proposed

Note: the owner asked for the feature; he has not confirmed this written decision.

## Date

2026-11-18

## Context

The owner asked to log a meal. He then widened it: add a generic log and attach documents to it, such as a photo. A meal is one use. A body photo or a sleep note is another. A fixed list of types would need a new release for each new use.

## Decision

- A log entry is a free note with a time: text plus any number of attached photos or files. It has no type and no fixed fields.
- Rule: an entry needs a note or at least one file. The text is up to 2000 characters. An entry holds up to 10 files.
- An entry is a fact. Only the app writes it, through `commands/entries` (ADR-002). It is a new table, so old rows stay valid.
- The coach reads entries: the text and the number of attachments of the last 7 days (at most 20), and the photos of the last 24 hours (at most 4) when the provider takes images.
- The AI does not estimate, score or rewrite an entry. It stays exactly what the user wrote. The AI never writes an entry.
- A deleted entry deletes its files. A file dropped by an edit is deleted too.
- The coach prompts get one short sentence that says what the field is. No new rules are added to them.
- Wording follows ADR-010: no medical words in copy, code or prompts.

## Consequences

- The app shows entries in the Home list between the sessions, by date.
- Entries do not change the plans, the dashboard or the reviews. Only the coach reads them.
- A photo of a body or a meal goes to the AI provider only when it is less than a day old and the provider takes images. This is the same path as a chat attachment.
- Open: the user cannot yet hide one entry from the coach. If the owner wants that, it is a new decision.
