import { starterTypes } from "../rules/planner";
import type { Repositories } from "../repositories/types";
import { summariseThreadJob } from "../ai/jobs";
import type { AiRunner } from "../ai/run-job";
import type { Session } from "../schema";
import type { ProposalService } from "./proposals";
import type { TaskQueue } from "./queue";

/** Invalidates stored proposals after writes and regenerates them in the background. */
export function createRefresher(repos: Repositories, proposals: ProposalService, ai: AiRunner, queue: TaskQueue) {
  const invalidate = () => {
    repos.plans.clear();
    repos.dashboards.clear();
    repos.predictions.clear();
  };

  const regenerate = () => {
    const types = [...new Set([...starterTypes, ...repos.sessions.list().filter((s) => s.kind === "gym").map((s) => s.type)])];
    for (const t of types) queue.enqueue(`plan:${t}`, async () => void (await proposals.generatePlan(t)));
    queue.enqueue("predictions", async () => void (await proposals.refreshPredictions()));
    queue.enqueue("dashboard:7", async () => void (await proposals.refreshDashboard(7)));
    queue.enqueue("dashboard:30", async () => void (await proposals.refreshDashboard(30)));
  };

  return {
    /** Goals, context, sessions or imports changed. */
    factsChanged() {
      invalidate();
      regenerate();
    },
    sessionWritten(s: Session) {
      queue.enqueue(`review:${s.id}`, async () => void (await proposals.reviewSession(s.id)));
      this.factsChanged();
    },
    sessionDeleted(id: string) {
      repos.reviews.delete(id);
      this.factsChanged();
    },
    threadChanged(threadId: string) {
      queue.enqueue(`summary:${threadId}`, async () => {
        const t = repos.threads.get(threadId);
        if (!t) return;
        const messages = repos.threads.messages(threadId).map((m) => ({ role: m.role, text: m.text }));
        const r = await ai.run(summariseThreadJob, { title: t.title, messages });
        const fresh = repos.threads.get(threadId);
        if (fresh) repos.threads.put({ ...fresh, summary: r.value.summary });
      });
    },
  };
}

export type Refresher = ReturnType<typeof createRefresher>;
