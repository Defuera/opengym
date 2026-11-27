# ADR-044: The Coach Talks Like a Coach, Not Like a Form

## Status

Accepted. Replaces one rule of the coach prompt that came with the coach turn (ADR-032): "do what the person asks, and only that", with no advice. It narrows the sentence of ADR-022 that says the coach "answers the question that was asked": the coach now also says what it thinks and asks one question back.

## Date

2026-11-27

## Context

The owner put the same knee-pain question to the coach of this app and to the Google Health coach, and compared them. His words (2026-11-27): "I think it's much more useful, and yeah, that's how I want the conversation to look like. Not with our coach. With our coach is useless."

The Google coach said what to do now, explained what is in that place and what it can mean, used his history, and asked a question back. Our coach answered in two thin lines.

## Cause

Verified by reading the stored prompt in `backend/convex/functions/model/ai/jobs/coachTurn.ts` (ROLE and DRAFTS). It told the coach to stay thin:

Old wording, ROLE: "Do what the person asks, and only that. Answer exactly the question asked, in a few short lines; write more only when they ask for everything. When you changed or drafted something, say what; do not say that nothing was changed unless they asked for a change. Give no advice, warnings, recommendations or disclaimers unless they ask."

Old wording, DRAFTS: " Do not give advice in a draft reply."

No ADR set this rule. The sentences were written with the first coach turn. ADR-022 had already removed the wording safeguards (no diagnosis, no treatment advice) while one owner tests; these sentences still kept the coach from using that freedom.

## Decision

- ROLE now says: "Talk like a good coach who has trained this person for a long time and knows their body and history. When they tell you how something feels or ask what you think, say what you think and why: what is in that place, what it can mean given their history, and what to do right now. Then ask the one question whose answer would change your advice. Keep it short enough to read between two sets. When you changed or drafted something, say what."
- The sentence about a photo or file with no question is unchanged.
- The sentence " Do not give advice in a draft reply." is removed.
- A turn with a `draft_log` action and a coach `question`: no code change is needed. `functions/jobs/coachTurn.ts` (the `save` mutation, line 157) passes the coach's question text to `logQuestion`/`proposalQuestion`, so the text stays visible and the draft's fixed buttons "Done" and "Add or change" stay. Only the model's own quick answers are dropped (ADR-032). A test in `tests/logChat.test.ts` guards this.
- Not changed: the record-reading rule ("add no advice or disclaimer" when the person asks what a record says), the debrief after a session (ADR-041), session building, parsing and entry reading.

## Evidence

Replayed by the reviewing agent on the owner's real message of 27 Nov 2026, 2 samples, without the photo. With the new wording both answers were good by the reviewing agent's reading: they said what to do now, what is in that place and what it can mean, and asked one question. This is two samples read by one agent, not a measurement. No eval case was run for this decision.

## Consequences

- Chat answers are longer and give advice by default. A medical-sounding answer is possible; ADR-022 applies (one owner tests; safeguards come before a second user).
- No eval case or unit test asserted the removed rule. `ch-declined-advice` (a declined piece of advice must not come back) still holds.
- Read the next real coach answers; if they run long, tighten "short enough to read between two sets".
