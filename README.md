# OpenGym

OpenGym is a gym companion app with an AI coach. It proposes sessions based on your history, lets you log sets/reps/weights with a clean UI, and gives you an AI summary at the end of each workout.

## Stack
- Next.js (App Router) + TypeScript
- Tailwind CSS
- PWA shell (installable on mobile)
- Local SQLite DB planned via Prisma (to be wired fully in early phases)

## MVP Overview
See `docs/MVP.md` for phased plan:
- Phase 0: Scaffold + local logging
- Phase 1: Rule-based session proposer
- Phase 2: OpenGym Coach Agent (AI adjustments + summaries)
- Phase 3+: Analytics, stats, and hosted DB

## Development

```bash
npm install
npm run dev
```

Then open http://localhost:3000

### Checks

- **Typecheck**: `npm run typecheck` - Run TypeScript compiler to check for type errors
- **Lint**: `npm run lint` - Run ESLint
- **Build**: `npm run build` - Full production build (includes typechecking)

## PWA

The app is intended to run as a Progressive Web App on mobile, so it can be installed on the home screen and used like a native app.

MVP Phase - Under active development.
// Test: verify Codex review pipeline is active
