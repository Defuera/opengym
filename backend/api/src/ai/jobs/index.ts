import type { JobDef } from "../run-job";
import { buildDashboardJob } from "./build-dashboard";
import { chatJob } from "./chat";
import { extractFromChatJob } from "./extract-from-chat";
import { importDataJob } from "./import-data";
import { planSessionJob } from "./plan-session";
import { predictActivityJob } from "./predict-activity";
import { reviewSessionJob } from "./review-session";
import { summariseThreadJob } from "./summarise-thread";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const jobRegistry: JobDef<any, any>[] = [
  planSessionJob,
  predictActivityJob,
  buildDashboardJob,
  chatJob,
  extractFromChatJob,
  summariseThreadJob,
  reviewSessionJob,
  importDataJob,
];

export const describeJobs = () => jobRegistry.map((j) => ({ name: j.name, description: j.description, fallback: j.fallbackDescription }));

export { buildDashboardJob, chatJob, extractFromChatJob, importDataJob, planSessionJob, predictActivityJob, reviewSessionJob, summariseThreadJob };
