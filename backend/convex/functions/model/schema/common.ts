import { z } from "zod";

/** The activity name of every gym session. The flavour (Upper, Legs, ...) is `focus`. */
export const GYM_TYPE = "Gym";

export const IdSchema = z.string().min(1).max(100);
export const MsSchema = z.number().int().nonnegative();

export const SessionSourceSchema = z.enum(["app", "import"]);
export const ProposalSourceSchema = z.enum(["ai", "rules"]);
export const ItemSourceSchema = z.enum(["user", "ai", "import"]);
