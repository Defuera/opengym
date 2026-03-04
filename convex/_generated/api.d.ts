/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as aiActions from "../aiActions.js";
import type * as aiActions_internal from "../aiActions_internal.js";
import type * as aiCoach from "../aiCoach.js";
import type * as aiCoachContext from "../aiCoachContext.js";
import type * as aiCoachDefs from "../aiCoachDefs.js";
import type * as aiCoachTools from "../aiCoachTools.js";
import type * as aiMemories from "../aiMemories.js";
import type * as aiMessages from "../aiMessages.js";
import type * as aiSessionPlanner from "../aiSessionPlanner.js";
import type * as aiSessionSummary from "../aiSessionSummary.js";
import type * as aiThreads from "../aiThreads.js";
import type * as aiTools from "../aiTools.js";
import type * as aiUserContext from "../aiUserContext.js";
import type * as analytics from "../analytics.js";
import type * as exercises from "../exercises.js";
import type * as sessions from "../sessions.js";
import type * as sets from "../sets.js";
import type * as users from "../users.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  aiActions: typeof aiActions;
  aiActions_internal: typeof aiActions_internal;
  aiCoach: typeof aiCoach;
  aiCoachContext: typeof aiCoachContext;
  aiCoachDefs: typeof aiCoachDefs;
  aiCoachTools: typeof aiCoachTools;
  aiMemories: typeof aiMemories;
  aiMessages: typeof aiMessages;
  aiSessionPlanner: typeof aiSessionPlanner;
  aiSessionSummary: typeof aiSessionSummary;
  aiThreads: typeof aiThreads;
  aiTools: typeof aiTools;
  aiUserContext: typeof aiUserContext;
  analytics: typeof analytics;
  exercises: typeof exercises;
  sessions: typeof sessions;
  sets: typeof sets;
  users: typeof users;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
