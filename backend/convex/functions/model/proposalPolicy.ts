/**
 * The ONE place that says whether a proposal needs the person's explicit "Agree" before it is applied (server code decides, never a
 * client). A program always needs it. A later kind may apply a small change at once (`none`), for example a change that came from chat.
 */
export type ProposalKind = "program";
export type ProposalOrigin = "request" | "feedback" | "chat";
export type Approval = "none" | "explicit";

const POLICY: Record<ProposalKind, Record<ProposalOrigin, Approval>> = {
  program: { request: "explicit", feedback: "explicit", chat: "explicit" },
};

export const approvalFor = (kind: ProposalKind, origin: ProposalOrigin): Approval => POLICY[kind][origin];
