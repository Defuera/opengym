# ADR-015: The User May Store Own Records; Limits Become Rules

## Status

Accepted. The clause "A record is never sent to an AI provider" is superseded by ADR-033 (2026-11-24).

## Date

2026-11-17

## Context

ADR-010 says: no medical wording in the app copy, the docs, the code or the AI prompts. The owner now wants to keep his own records in the app (for example the text of a scan report) and to track body limits (wrists, left knee) in an "About me" section. He accepted this change on 2026-11-17.

## Decision

- The app still never diagnoses, never advises treatment and never uses clinical wording in its own copy, code or AI prompts. That part of ADR-010 stays.
- The user may store his own records. The app keeps the text word for word. The app does not interpret it.
- A record is never sent to an AI provider. The AI receives only the training rules of a limit.
- A limit has a body part, a status (active, improving, cleared) and rules in training words: avoid, light, do.
- An "avoid" rule is a hard check in code. A plan that breaks it is rejected, as with the plan safety limits (ADR-004).
- After a session, the app may ask how a limited body part felt. The answer is a fact the user gives; it is stored with the session date.

## Consequences

- ADR-010 is partly replaced: user-entered records are exempt from the wording rule; everything the app or the AI writes is not.
- Prompt builders must take rules from limits and must not read records. A test must check this. (Superseded by ADR-033: the coach and the planning jobs now read records.)
- Coach notes about body limits move into limits. Other coach notes become preferences in "About me".
