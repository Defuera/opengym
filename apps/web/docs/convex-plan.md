# Convex Integration Plan

This document outlines the strategy for integrating Convex as the backend for OpenGym, replacing the current in-memory repository implementation.

## Overview

Convex will serve as the production database and real-time backend for OpenGym. The repository pattern allows us to swap implementations without changing any UI or API route code.

## Current State

- **In-memory repository**: `src/lib/repositories/workout-repository.ts`
- **Repository interface**: Defined by the exported `workoutRepository` object methods
- **Data types**: Defined in `src/lib/repositories/types.ts`
- **Usage**: Pages and API routes import from `@/lib/repositories`

## Target Data Model in Convex

The Convex schema mirrors the existing domain types with minor adaptations:

### Tables

1. **users**
   - `name: string`
   - `createdAt: number` (timestamp)

2. **sessions**
   - `userId: Id<"users">`
   - `date: number` (timestamp)
   - `status: "planned" | "active" | "completed"`
   - `createdAt: number`
   - `updatedAt: number`
   - Index: `by_user` on `userId`

3. **exercises**
   - `sessionId: Id<"sessions">`
   - `name: string`
   - `muscleGroup: string`
   - `order: number`
   - Index: `by_session` on `sessionId`

4. **sets**
   - `exerciseId: Id<"exercises">`
   - `reps: number`
   - `weight: number`
   - `order: number`
   - Index: `by_exercise` on `exerciseId`

### Key Differences from In-Memory Implementation

- **IDs**: Convex uses `Id<TableName>` types instead of strings
- **Dates**: Stored as timestamps (`number`) instead of `Date` objects
- **Relationships**: Enforced via typed IDs and indexes

## Repository Interface Mapping

The existing `workoutRepository` interface will be implemented using Convex queries and mutations:

| Repository Method | Convex Implementation |
|-------------------|----------------------|
| `listRecentSessionsForUser` | Query sessions by user index, then fetch related exercises and sets |
| `getSessionWithDetails` | Query session by ID, then fetch related exercises and sets |
| `getRecentCompletedSessions` | Query sessions filtered by status, then fetch related data |
| `createSession` | Mutation that inserts session, exercises, and sets transactionally |
| `updateSessionStatus` | Mutation that patches session status |
| `updateSet` | Mutation that patches set data |

## Migration Strategy

### Phase 1: Convex Setup (Current)

- ✅ Install Convex package
- ✅ Create `convex/` directory with schema and initial functions
- ✅ Add Convex client provider for Next.js
- ✅ Configure `NEXT_PUBLIC_CONVEX_URL` environment variable
- ⏳ Deploy Convex backend and obtain deployment URL

### Phase 2: Create Convex Repository Implementation

1. Create `src/lib/repositories/workout-repository-convex.ts`
2. Implement all methods from the current repository interface
3. Handle type conversions (Date ↔ number, string IDs ↔ Convex IDs)
4. Add necessary Convex queries/mutations in `convex/` directory
5. Create query helpers for fetching nested data (sessions with exercises and sets)

### Phase 3: Switch-Over

**Option A: Simple Switch (Recommended for MVP)**
- Update `src/lib/repositories/index.ts` to export Convex repository
- Remove in-memory implementation
- Test all flows (home page, session creation, session summary)

**Option B: Dual-Write (If data preservation needed)**
- Write to both in-memory and Convex simultaneously
- Read from Convex
- Keep for one deployment cycle, then remove in-memory

### Phase 4: Testing & Validation

1. Verify all pages load correctly:
   - `/` (home page with recent sessions)
   - `/session/new` (session creation)
   - `/session/[id]` (active session)
   - `/session/[id]/summary` (session summary)

2. Test data flows:
   - Creating a new session
   - Updating sets during workout
   - Completing a session
   - Viewing workout history

3. Verify no UI changes are required

## Implementation Details

### Type Conversions

The Convex repository will need helpers to convert between domain types and Convex storage:

```typescript
// Date to timestamp
const toTimestamp = (date: Date): number => date.getTime();
const fromTimestamp = (ts: number): Date => new Date(ts);

// Convex ID to string (for compatibility)
const idToString = <T extends string>(id: Id<T>): string => id;
const stringToId = <T extends string>(str: string): Id<T> => str as Id<T>;
```

### Fetching Nested Data

Convex queries should efficiently fetch sessions with their exercises and sets:

```typescript
// Example pattern
export const getSessionWithDetails = query({
  args: { sessionId: v.id("sessions") },
  handler: async (ctx, args) => {
    const session = await ctx.db.get(args.sessionId);
    if (!session) return null;

    const exercises = await ctx.db
      .query("exercises")
      .withIndex("by_session", q => q.eq("sessionId", args.sessionId))
      .collect();

    const exercisesWithSets = await Promise.all(
      exercises.map(async (exercise) => {
        const sets = await ctx.db
          .query("sets")
          .withIndex("by_exercise", q => q.eq("exerciseId", exercise._id))
          .collect();
        return { ...exercise, sets };
      })
    );

    return { ...session, exercises: exercisesWithSets };
  },
});
```

### Preserving the Repository Abstraction

The key principle is that **no code outside `src/lib/repositories/` should change**. This means:

- Pages continue to import from `@/lib/repositories`
- API routes continue to call the same repository methods
- Return types remain compatible (convert Convex types back to domain types)
- The repository layer handles all Convex-specific logic

## Environment Configuration

Required environment variables:

```bash
# .env.local or .env
NEXT_PUBLIC_CONVEX_URL="https://your-deployment.convex.cloud"
```

Obtain this URL by:
1. Running `npx convex dev` (development)
2. Or deploying with `npx convex deploy` (production)
3. Or from the Convex dashboard

## Rollback Plan

If issues arise during migration:

1. Revert `src/lib/repositories/index.ts` to export in-memory repository
2. Data in Convex is preserved and can be migrated back if needed
3. No changes to UI or API routes means quick rollback

## Next Steps for Implementation

When ready to proceed with migration:

1. Set up Convex deployment and get URL
2. Implement Convex repository following the interface
3. Create comprehensive Convex queries/mutations
4. Test locally with `npx convex dev`
5. Switch the export in `src/lib/repositories/index.ts`
6. Deploy and verify all functionality
7. Remove in-memory implementation after successful deployment

## Benefits of Convex

- **Real-time updates**: Subscribe to live data changes
- **Optimistic updates**: Built-in optimistic UI support
- **Transactional**: Mutations are automatically transactional
- **Type-safe**: Full TypeScript support with generated types
- **Serverless**: No database management required
- **File storage**: Can add file storage for future features (photos, videos)
