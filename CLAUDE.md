# OpenGym Claude Guide

Short, always-loaded guide for coding agents working on this repo.

## Project Snapshot

- Next.js (App Router) + TypeScript + Tailwind CSS
- Mobile-first PWA gym companion with an AI coach
- Core flows:
  - Propose a workout session based on history / external activity
  - Let user log sets / reps / weights during the session
  - Show an AI-generated summary / guidance at the end

## Next.js App Router Cheatsheet

- Routes live under `src/app` using the App Router.
- Use **server components by default**.
  - Add `"use client"` only when you need browser APIs, local interactive state, or event handlers.

### Basic Routing

- `src/app/page.tsx` → `/`
- `src/app/session/new/page.tsx` → `/session/new`
- `src/app/session/[id]/page.tsx` → `/session/[id]`
- `src/app/session/[id]/summary/page.tsx` → `/session/[id]/summary`

### Data Fetching

- Prefer **async server components** for data loading:

  ```ts
  // example
  export default async function Page() {
    const data = await getData();
    return <UI data={data} />;
  }
  ```

- For client-side updates, expose minimal API routes under `src/app/api/.../route.ts`.
- Use standard `GET` / `POST` handlers with Next.js `Request` / `Response` helpers.

### Navigation & Metadata

- Use `next/link` for navigation inside the app.
- Keep metadata simple via `export const metadata` in layout/page files when needed.

## PWA Expectations

- App is intended to be **installable on mobile** and used full-screen.
- Avoid changes that would break basic PWA behavior (manifest, icons, stable routes).
- Keep core flows simple and fast: minimal blocking calls during in-gym usage.

## House Rules (See docs/guides)

- `docs/guides/commit-guide.md` → commit format and constraints.
- `docs/guides/ui-components-guide.md` → how to build and use UI components.
- `docs/guides/guide-writing-guide.md` → how to write new guides for agents.
- `docs/guides/js-modularity-guide.md` → file sizing, splitting, and module patterns.

Always treat these guides as **hard constraints**, not suggestions.

## Data Access Pattern

- ALWAYS use repositories for data access:
  - Import from `@/lib/repositories` in pages and API routes.
  - NEVER access database clients or storage directly.
  - Repository layer is at `src/lib/repositories/`.

- **Backend Target: Convex**
  - Convex is the intended production backend for OpenGym.
  - Current implementation uses in-memory repositories for development.
  - Repositories MUST be designed to be swappable between implementations.
  - All repository interfaces should support both in-memory and Convex backends.
  - See `docs/convex-plan.md` for migration strategy and implementation details.

## Deployment

- **Frontend (Vercel):** Auto-deploys on push to `main`.
- **Backend (Convex):** Must be deployed separately. After changing any file in `convex/`, run:
  ```bash
  npx convex deploy
  ```
  Convex deployment URL: `https://wary-mockingbird-65.eu-west-1.convex.cloud`
- **Always deploy Convex before verifying the app** if you touched `convex/` files.

## How To Work (Claude Code)

- ALWAYS follow the Commit Guide:
  - Conventional commits: `<type>[scope]: <description>`
  - Short, imperative, lowercase, no trailing period.
  - No attribution or Co-Authored-By lines.

- ALWAYS keep files small and modular per JS Modularity Guide:
  - Split when files grow large or contain multiple concerns.
  - Prefer extracting logical modules over piling logic into a single file.

- PREFER server components:
  - Add `"use client"` only when interactivity or browser-only APIs are required.

- NEVER add new UI libraries or styling systems:
  - Use Tailwind + simple React components.

- NEVER change deployment or Vercel configuration unless the task explicitly asks for it.

- When in doubt:
  - Check `docs/` and existing patterns first.
  - Make minimal, focused changes with clear commit messages.
