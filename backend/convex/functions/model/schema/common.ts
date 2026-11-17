import { z } from "zod";

/** The default activity name of a session with sets (ADR-016: any name is allowed; the flavour is `focus`). */
export const GYM_TYPE = "Gym";

export const IdSchema = z.string().min(1).max(100);
export const MsSchema = z.number().int().nonnegative();

export const SessionSourceSchema = z.enum(["app", "import"]);
export const ProposalSourceSchema = z.enum(["ai", "rules"]);
export const ItemSourceSchema = z.enum(["user", "ai", "import"]);
