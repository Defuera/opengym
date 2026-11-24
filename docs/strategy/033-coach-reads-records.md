# ADR-033: The Coach Reads the Person's Records

## Status

Accepted

Note: the owner asked for this on 2026-11-24: "What is the point of records of ai cannot read them?" He said it after the coach answered "no diagnoses are logged" while a scan report was stored as a record on his left knee limit.

## Date

2026-11-24

## Context

ADR-015 says a record is never sent to an AI provider. A record is the person's own text for a limit, for example a scan report, word for word. With that rule the coach could not answer what the records say, and it said nothing was stored (verified in the `coach_turn` trace of the owner's test chat, 2026-11-24).

## Decision

- The jobs that carry the person's limits now also carry the records of those limits: `coach_turn`, `build_session`, `plan_session`, `review_session` and `build_program`. One place builds it: `limitsForPrompt` (`model/rules/limits.ts`), fed by `limitsForAi` (`lib/limitsDb.ts`).
- A record goes as `{ title, date?, text, textWasCut? }` under its limit. Records of a cleared limit go too, with the status `cleared` and no rules.
- Size: at most 5 records per limit (newest by date first) and at most 8000 characters per record (the storage limit is 8000 already). A longer text is cut and carries `textWasCut: true`.
- Records are text only. They have no files.
- The app keeps a record word for word. No AI function writes, changes or deletes a record. The lists the coach may change (`limitsYouMayChange`) still carry no record.
- Not changed: the rule against medical advice in the app's own copy is a wording safeguard that ADR-022 already lifts for AI output. The prompt tells the coach to report what a record says, with no advice or disclaimer unless asked.

## Consequences

- ADR-015: the clause "A record is never sent to an AI provider" is superseded. The rest of ADR-015 holds.
- `docs/requirements.md` (frozen) changed on this one line, with the owner's words.
- The test that asserted that no job prompt holds a record now asserts the reverse (`tests/limitsAi.test.ts`, `tests/logChat.test.ts`).
- Cost: a prompt with records is longer, by up to 40000 characters per limit in the worst case.
