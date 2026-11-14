import type { AiRunner, Logger } from "./ai/run-job";
import type { Repositories } from "./repositories/types";
import type { ImportRunner } from "./services/import-runner";
import type { ProposalService } from "./services/proposals";
import type { TaskQueue } from "./services/queue";
import type { Refresher } from "./services/refresh";

export interface AppDeps {
  token: string;
  version: string;
  repos: Repositories;
  ai: AiRunner;
  queue: TaskQueue;
  logger: Logger;
  now: () => number;
}

export interface AppContext extends AppDeps {
  proposals: ProposalService;
  refresher: Refresher;
  importRunner: ImportRunner;
}
