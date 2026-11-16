# Gym Days (OpenGym) — Agent Guide

Short, always-loaded guide for coding agents working in this monorepo. Read this first. Then read the `CLAUDE.md` or README of the part you touch.

## What this is

Gym Days (repo name `opengym`) is a gym and activity tracker with an AI coach. The user logs sets fast in the gym. An AI engine proposes sessions, ordering and dashboard modules. The AI never edits what the user logged.

## Repo map

```
opengym/
├── apps/
│   ├── mobile/       # Flutter app — the product going forward (README.md)
│   ├── web/          # OLD Next.js PWA + Convex. Deploys to Vercel from main (CLAUDE.md)
│   └── prototype/    # One-page web prototype; behaviour reference for the Flutter app
├── backend/
│   └── api/          # Standalone TypeScript API: Hono, zod, better-sqlite3, AI engine (README.md)
├── infra/            # Deploy scripts (Cloud Run)
├── docs/
│   ├── api-contract.md   # Schema, endpoints, AI jobs. Backend and app both follow it
│   ├── requirements.md   # The owner's requirements, with plain wording
│   ├── design.md         # Design canvas link, artboards, visual tokens
│   ├── guides/           # House rules for agents (hard constraints)
│   └── strategy/         # Numbered ADRs and their index
└── .github/workflows/    # quality.yml (path-filtered checks), codex-review.yml
```

Each part has its own dependencies. There is no root `package.json`.

## Rules

- Follow `docs/guides/*` as hard constraints, not suggestions:
  - `docs/guides/commit-guide.md` — commit format.
  - `docs/guides/ui-components-guide.md` — UI components.
  - `docs/guides/guide-writing-guide.md` — how to write guides.
  - `docs/guides/js-modularity-guide.md` — file size and module splitting.
- Commits use conventional commits: `<type>[scope]: <description>`. Lowercase, imperative, under 50 characters, no period. No attribution or Co-Authored-By lines. See `docs/guides/commit-guide.md`.
- Never commit to `main` directly. `main` auto-deploys the web app to Vercel. Work on a branch and open a pull request.
- Never commit secrets or `.env` files. Use `.env.example` for names only. Never print a key or token in a log, comment or file.
- Record each non-trivial decision as a new ADR in `docs/strategy/` and add it to the index there. Mark a decision the owner has not confirmed as `Proposed`. Do not state facts or metrics that no source supports.
- The AI never writes facts. Sessions and sets are written only by the app or by an import the user starts. AI output is a proposal tagged `source: "ai"` or `"rules"` (ADR-002).
- The AI is never in the tap path. Logging is local and offline-first (ADR-003).
- Every AI job follows this pipeline: prompt, provider, JSON, zod validation, one retry, plain code fallback. Keep the plan safety limits (ADR-004).
- No medical wording anywhere: not in the UI, docs, code or AI prompts (ADR-010).
- Keep files small and modular. Keep Flutter widgets standalone: `lib/widgets` imports only Flutter, `theme.dart` and other widgets.
- Access data only through repositories. They are interfaces, so the store can change later.
- `docs/api-contract.md` is the contract between backend and app. Change it only together with both sides.
- Write prose in short sentences, active voice, plain words. Name a rule by what it says, not by a code alone.

## Per-part notes

- `apps/mobile`: see `apps/mobile/README.md`. Run `flutter analyze` and `flutter test` before you push. Flutter 3.44.x stable.
- `backend/api`: see `backend/api/README.md`. Node 22. Run `npm run typecheck` and `npm test`.
- `apps/web`: see `apps/web/CLAUDE.md`. Run commands from `apps/web`. The Vercel Root Directory must be `apps/web`.

## Worktrees

Fresh worktrees lack gitignored files. `.worktreeinclude` lists the build-critical ones (paths only, never values). Keep it current when you add a new local config file.

## When in doubt

- Read `docs/strategy/README.md` for settled decisions. Read `docs/requirements.md` for what the owner asked for.
- Open questions stay open. Do not fill them with assumptions.
- Make minimal, focused changes with clear commit messages.
