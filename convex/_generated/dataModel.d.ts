/* eslint-disable */
/**
 * Generated data model types.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type {
  DataModelFromSchemaDefinition,
} from "convex/server";
import type { GenericId } from "convex/values";
import schema from "../schema.js";

/**
 * The names of all of your Convex tables.
 */
export type TableNames = "users" | "sessions" | "exercises" | "sets";

/**
 * The type of a document stored in Convex.
 */
export type Doc<TableName extends TableNames> =
  TableName extends "users"
    ? {
        _id: Id<"users">;
        _creationTime: number;
        name: string;
        createdAt: number;
      }
    : TableName extends "sessions"
      ? {
          _id: Id<"sessions">;
          _creationTime: number;
          userId: Id<"users">;
          date: number;
          status: "planned" | "active" | "completed";
          createdAt: number;
          updatedAt: number;
        }
      : TableName extends "exercises"
        ? {
            _id: Id<"exercises">;
            _creationTime: number;
            sessionId: Id<"sessions">;
            name: string;
            muscleGroup: string;
            order: number;
          }
        : TableName extends "sets"
          ? {
              _id: Id<"sets">;
              _creationTime: number;
              exerciseId: Id<"exercises">;
              reps: number;
              weight: number;
              order: number;
            }
          : never;

export type DataModel = DataModelFromSchemaDefinition<typeof schema>;

export type Id<TableName extends TableNames> = GenericId<TableName>;
