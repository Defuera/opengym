# Gym Days (OpenGym)

Gym Days is a gym and activity tracker with an AI coach. Logging is fast: one screen, one or two taps per action, and it works offline. The AI proposes the next session, the order of predictions and the home dashboard. It never edits what you logged.

## Folder map

| Folder | What it is | Docs |
|--------|-----------|------|
| `apps/mobile` | Flutter app. The product going forward. | [README](apps/mobile/README.md) |
| `apps/web` | Old Next.js PWA with Convex. Moved here as-is. | [CLAUDE.md](apps/web/CLAUDE.md), [docs](apps/web/docs) |
| `apps/prototype` | One-page web prototype. Behaviour reference for the Flutter app. | open `apps/prototype/index.html` |
| `backend/api` | Standalone TypeScript API with the AI engine (Hono, zod, SQLite). | [README](backend/api/README.md) |
| `infra` | Deploy scripts for the backend on Google Cloud Run. | scripts in the folder |
| `docs` | API contract, requirements, design, guides and ADRs. | see below |

## Documents

- [API contract](docs/api-contract.md) — schema, endpoints and AI jobs.
- [Requirements](docs/requirements.md) — what the owner asked for, including open questions.
- [Design](docs/design.md) — design canvas, artboards and visual tokens.
- [Decisions (ADRs)](docs/strategy/README.md) — numbered decision records.
- [Guides](docs/guides) — house rules for contributors and agents.
- [Agent guide](CLAUDE.md) — rules for coding agents.

## How to run each part

Each part has its own dependencies. Run commands from the part's folder.

- **Backend API** (`backend/api`, Node 22): `npm install`, `cp .env.example .env`, set the AI provider, key and model, then `npm run dev`. Test with `npm test`. Full steps: [backend/api/README.md](backend/api/README.md).
- **Mobile app** (`apps/mobile`, Flutter 3.44.x stable): `flutter pub get`, `flutter analyze`, `flutter test`, then `flutter run`. iPhone install steps and the widget gallery: [apps/mobile/README.md](apps/mobile/README.md).
- **Web app** (`apps/web`): `npm install`, `npm run dev`, then open http://localhost:3000. Checks: `npm run typecheck`, `npm run lint`, `npm test`. Convex notes: [apps/web/CLAUDE.md](apps/web/CLAUDE.md).
- **Prototype** (`apps/prototype`): open `index.html` in a browser.

## Deployment

- **`main` auto-deploys the web app to Vercel.** Never commit to `main` directly. Use a branch and a pull request.
- The Vercel project must set Root Directory to `apps/web`. This is a manual setting in the Vercel dashboard.
- The Convex backend of the web app deploys separately: run `npx convex deploy` from `apps/web` after you change `apps/web/convex/`.
- The new backend is planned for Google Cloud Run with SQLite on a Cloud Storage volume, on one instance. This is proposed, not confirmed. See [ADR-009](docs/strategy/009-cloud-run-hosting.md).

## Checks in CI

`.github/workflows/quality.yml` runs checks only for the parts that changed: backend, mobile and web. `codex-review.yml` posts an automated review on pull requests.
