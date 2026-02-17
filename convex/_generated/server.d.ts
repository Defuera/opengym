/* eslint-disable */
/**
 * Generated server utilities.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import {
  actionGeneric,
  httpActionGeneric,
  queryGeneric,
  mutationGeneric,
  internalActionGeneric,
  internalMutationGeneric,
  internalQueryGeneric,
} from "convex/server";
import type { DataModel } from "./dataModel.js";

/**
 * Define a query in this Convex app's public API.
 *
 * This function will be allowed to read your Convex database and will be accessible from the client.
 *
 * @param func - The query function. It receives a `QueryCtx` as its first argument.
 * @returns The wrapped query. Include this as an `export` to add it to your app's API.
 */
export const query = queryGeneric as typeof queryGeneric<DataModel>;

/**
 * Define a query that is only accessible from other Convex functions (but not from the client).
 *
 * This function will be allowed to read from your Convex database. It will not be accessible from the client.
 *
 * @param func - The query function. It receives a `QueryCtx` as its first argument.
 * @returns The wrapped query. Include this as an `export` to add it to your app's API.
 */
export const internalQuery =
  internalQueryGeneric as typeof internalQueryGeneric<DataModel>;

/**
 * Define a mutation in this Convex app's public API.
 *
 * This function will be allowed to modify your Convex database and will be accessible from the client.
 *
 * @param func - The mutation function. It receives a `MutationCtx` as its first argument.
 * @returns The wrapped mutation. Include this as an `export` to add it to your app's API.
 */
export const mutation = mutationGeneric as typeof mutationGeneric<DataModel>;

/**
 * Define a mutation that is only accessible from other Convex functions (but not from the client).
 *
 * This function will be allowed to modify your Convex database. It will not be accessible from the client.
 *
 * @param func - The mutation function. It receives a `MutationCtx` as its first argument.
 * @returns The wrapped mutation. Include this as an `export` to add it to your app's API.
 */
export const internalMutation =
  internalMutationGeneric as typeof internalMutationGeneric<DataModel>;

/**
 * Define an action in this Convex app's public API.
 *
 * An action is a function which can execute any JavaScript code, including non-deterministic
 * code and code with side-effects, like calling third-party services.
 * They can be run in Convex's JavaScript environment or in Node.js using the "use node" directive.
 * They can interact with the database indirectly by calling queries and mutations using the {@link ActionCtx}.
 *
 * @param func - The action function. It receives an `ActionCtx` as its first argument.
 * @returns The wrapped action. Include this as an `export` to add it to your app's API.
 */
export const action = actionGeneric as typeof actionGeneric<DataModel>;

/**
 * Define an action that is only accessible from other Convex functions (but not from the client).
 *
 * @param func - The action function. It receives an `ActionCtx` as its first argument.
 * @returns The wrapped action. Include this as an `export` to add it to your app's API.
 */
export const internalAction =
  internalActionGeneric as typeof internalActionGeneric<DataModel>;

/**
 * Define an HTTP action.
 *
 * This function will be used to respond to HTTP requests received by a Convex
 * deployment if the requests matches the path and method where this action
 * is routed. Be sure to route your action in `convex/http.js`.
 *
 * @param func - The function. It receives an `ActionCtx` as its first argument, and a `Request` object as its second.
 * @returns The wrapped action. Import this function from `convex/http.js` and route it to hook it up.
 */
export const httpAction = httpActionGeneric as typeof httpActionGeneric<DataModel>;
