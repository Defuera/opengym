# ADR-005: Interchangeable AI Providers via Plain Fetch

## Status

Accepted

## Date

2026-11-16

## Context

The owner wants to switch between Anthropic, DeepSeek and OpenAI. He also wants to test with his own API keys. Source: REQUIREMENTS.md (providers interchangeable); DECISIONS.md.

## Decision

- Providers are `anthropic`, `openai`, `deepseek`, `mock` and `none`.
- `none` means rules only. `mock` needs no key and is used in tests.
- Each adapter uses plain `fetch`. The backend uses no vendor SDK.
- Model ids come from environment variables. They are never hard-coded.
- `AI_PROVIDER` selects the provider. The server exits with a message if the key or model for that provider is missing.
- DeepSeek has no image input.

## Consequences

- Switching provider is a config change and a restart.
- No real provider call has been verified yet. Only the mock provider and stubbed requests were tested (DECISIONS.md, known gaps).
- Each adapter must be checked against the real API before release.
