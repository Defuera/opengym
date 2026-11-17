# ADR-010: No Medical Wording

## Status

Partly replaced by ADR-015 (the user may store his own records)

## Date

2026-11-16

## Context

The owner set a constraint: nothing medical. No rehab framing, no doctor report, no clinical language. An injury is one context input, not the product. Source: REQUIREMENTS.md (constraints section); DECISIONS.md.

## Decision

- No medical wording in the app copy, the docs, the code or the AI prompts.
- Example from DECISIONS.md: write "Ankle — train around it".
- A goal may still be "release pain" or "work through an injury". The wording stays plain and non-clinical.
- The product shows no invented metrics and no testimonials.

## Consequences

- Prompt reviews must check for clinical terms.
- Agents must follow this rule in generated text too.
