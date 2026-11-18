import type { Infer } from "convex/values";
import { START_FEEDBACK_KEEP } from "./constants";
import type { previousPlan } from "./validators";

type Compact = Infer<typeof previousPlan>;
type PlanLike = { exercises: ({ name: string; measure?: string; sets: unknown[] } & Record<string, unknown>)[] };

/** The plan of a proposal as exercise names with sets (no notes), or undefined when there is none. */
export function compactPlan(plan: PlanLike | undefined): Compact | undefined {
  if (!plan || plan.exercises.length === 0) return undefined;
  return plan.exercises.map(({ name, measure, sets }) => (measure === "time" ? { name, measure: "time" as const, sets } : { name, sets })) as Compact;
}

/** The feedback chain of a rebuild: the earlier rounds, then this one; the oldest is dropped past the limit. */
export const feedbackChain = (earlier: string[] | undefined, feedback: string): string[] => [...(earlier ?? []), feedback].slice(-START_FEEDBACK_KEEP);
