import { z } from "zod";
import { IdSchema, MsSchema, SessionSourceSchema } from "./common";

export const SetEntrySchema = z.object({
  reps: z.number().int().min(0).max(100),
  kg: z.number().min(0).max(500),
  max: z.boolean(),
  /** One more rep was tried after `reps` and not completed. */
  failed: z.boolean().optional(),
  at: z.number().optional(),
});

export const ExerciseSchema = z.object({
  name: z.string().min(1).max(60),
  sets: z.array(SetEntrySchema).max(12),
});

export const SessionSchema = z
  .object({
    id: IdSchema,
    kind: z.enum(["gym", "activity"]),
    type: z.string().min(1).max(40),
    startedAt: MsSchema,
    endedAt: MsSchema,
    exercises: z.array(ExerciseSchema).max(15),
    minutes: z.number().int().nonnegative().optional(),
    distanceKm: z.number().nonnegative().optional(),
    note: z.string().optional(),
    source: SessionSourceSchema,
    importId: z.string().optional(),
  })
  .refine((s) => s.kind === "gym" || s.exercises.length === 0, {
    message: "activity sessions must have no exercises",
    path: ["exercises"],
  })
  .refine((s) => s.endedAt >= s.startedAt, {
    message: "endedAt must not be before startedAt",
    path: ["endedAt"],
  });

export type SetEntry = z.infer<typeof SetEntrySchema>;
export type Exercise = z.infer<typeof ExerciseSchema>;
export type Session = z.infer<typeof SessionSchema>;
