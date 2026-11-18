# ADR-022: No Wording Safeguards on the Coach While One Owner Tests

## Status

Accepted

Note: the owner decided this in the session of 2026-11-18. His words: "we should remove all these safeguards and start just playing around and working. I'm the only user now and I'm testing it. No need for safeguards. We'll add safeguards later and test with them."

## Date

2026-11-18

## Context

ADR-010 kept medical wording out of the app and the AI. Every coach prompt said: training only, no diagnosis, no rehab, no medical language, no treatment advice, and a sore body part is a training preference and nothing more. In a chat about a sore arm (with photos) the coach then could not name the muscle, did not answer how to check it or how to recover, repeated itself, and listed all stored limits twice.

The app has one user, the owner, who tests it.

## Decision

- The wording safeguards of ADR-010 are removed from the AI prompts: the "training only" rule, the "no diagnosis, no rehab, no medical language, no treatment advice" rule, the "respond only with training adjustments" rule of the chat, the chat rule that listed all stored limits, and "training words only" in the session builder.
- The coach answers the question that was asked, with what it knows about the body and about training, and may ask a question back.
- The chat sends the photos of the earlier user messages in the history (newest 6), not only the photos of the newest message.
- What stays: the coach never invents logged data; a movement that a limit marks avoid is never planned (the limits rule and the code checks); the plan safety limits of ADR-004; the user's own records never go to an AI provider (ADR-015).
- This supersedes ADR-010 for AI output for now. The fixed UI copy of the app is not changed by this decision.

## Consequences

- The coach may name muscles, describe a simple check, and give recovery advice. Its answers are not reviewed by anyone.
- Before a second person uses the app, the safeguards must be designed again and tested (the owner: "We'll add safeguards later and test with them").
