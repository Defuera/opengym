import { z } from "zod";
import { PART_KEYS } from "../rules/muscles";

export const PartSchema = z.enum(PART_KEYS);
export const LimitStatusSchema = z.enum(["active", "improving", "cleared"]);
export const RuleKindSchema = z.enum(["avoid", "light", "do"]);
export const FeelingSchema = z.enum(["fine", "noticed", "bad"]);

const IdSchema = z.string().min(1).max(100);
const DateSchema = z.string().regex(/^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/, "must be YYYY-MM-DD");
const MonthSchema = z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/, "must be YYYY-MM");

export const RuleSchema = z.object({
  kind: RuleKindSchema,
  text: z.string().min(1).max(120),
  exercises: z.array(z.string().min(1).max(60)).max(20).optional(),
});

export const LimitSchema = z.object({
  limitId: IdSchema,
  part: PartSchema,
  title: z.string().min(1).max(40),
  status: LimitStatusSchema,
  since: MonthSchema.optional(),
  rules: z.array(RuleSchema).max(12),
});

/** The user's own text. Kept word for word; never sent to an AI provider (ADR-015). */
export const RecordInputSchema = z.object({
  recordId: IdSchema,
  limitId: IdSchema,
  title: z.string().min(1).max(60),
  date: DateSchema.optional(),
  text: z.string().min(1).max(8000),
});

export const CheckinSchema = z.object({
  checkinId: IdSchema,
  limitId: IdSchema,
  sessionId: IdSchema.optional(),
  at: z.number().int().nonnegative(),
  feeling: FeelingSchema,
});

export type Rule = z.infer<typeof RuleSchema>;
export type Limit = z.infer<typeof LimitSchema>;
export type RecordInput = z.infer<typeof RecordInputSchema>;
export type Checkin = z.infer<typeof CheckinSchema>;

/** What an AI job may read of a limit. No records, no exercise lists. */
export interface PromptLimit {
  part: string;
  title: string;
  status: "active" | "improving" | "cleared";
  rules: { kind: "avoid" | "light" | "do"; text: string }[];
}
