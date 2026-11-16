import { z } from "zod";

export const IdSchema = z.string().min(1).max(100);
export const MsSchema = z.number().int().nonnegative();

export const SessionSourceSchema = z.enum(["app", "import"]);
export const ProposalSourceSchema = z.enum(["ai", "rules"]);
export const ItemSourceSchema = z.enum(["user", "ai", "import"]);
