import type {
  ContextItem,
  DashboardSpec,
  FileMeta,
  Goal,
  ImportJob,
  Message,
  Plan,
  Prediction,
  Review,
  Session,
  Thread,
} from "../schema";

export interface SessionRepository {
  upsert(s: Session): Session;
  get(id: string): Session | null;
  delete(id: string): boolean;
  /** endedAt > since, oldest first. */
  list(since?: number): Session[];
  deleteByImport(importId: string): number;
}

export interface GoalRepository {
  list(): Goal[];
  get(id: string): Goal | null;
  put(g: Goal): Goal;
  delete(id: string): boolean;
  deleteByImport(importId: string): number;
}

export interface ContextRepository {
  list(): ContextItem[];
  get(id: string): ContextItem | null;
  put(c: ContextItem): ContextItem;
  delete(id: string): boolean;
  deleteByImport(importId: string): number;
}

export interface ThreadRepository {
  list(): Thread[];
  get(id: string): Thread | null;
  put(t: Thread): Thread;
  /** Also removes the thread's messages. */
  delete(id: string): boolean;
  messages(threadId: string): Message[];
  addMessage(m: Message): Message;
}

export interface FileRepository {
  save(meta: FileMeta, bytes: Uint8Array): FileMeta;
  meta(id: string): FileMeta | null;
  bytes(id: string): Uint8Array | null;
}

export interface ImportRepository {
  put(j: ImportJob): ImportJob;
  get(id: string): ImportJob | null;
  list(): ImportJob[];
  delete(id: string): boolean;
}

export interface PlanRepository {
  get(type: string): Plan | null;
  put(p: Plan): Plan;
  clear(): void;
}

export interface DashboardSpecRepository {
  get(days: number): DashboardSpec | null;
  put(days: number, spec: DashboardSpec): void;
  clear(): void;
}

export interface PredictionRepository {
  get(): Prediction[] | null;
  put(p: Prediction[]): void;
  clear(): void;
}

export interface ReviewRepository {
  get(sessionId: string): Review | null;
  put(r: Review): Review;
  delete(sessionId: string): void;
}

export interface Repositories {
  sessions: SessionRepository;
  goals: GoalRepository;
  context: ContextRepository;
  threads: ThreadRepository;
  files: FileRepository;
  imports: ImportRepository;
  plans: PlanRepository;
  dashboards: DashboardSpecRepository;
  predictions: PredictionRepository;
  reviews: ReviewRepository;
  close(): void;
}
