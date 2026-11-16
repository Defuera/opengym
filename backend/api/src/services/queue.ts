import type { Logger } from "../ai/run-job";

export interface TaskQueue {
  enqueue(name: string, fn: () => Promise<void> | void): void;
  /** Runs until nothing is pending or running. */
  drain(): Promise<void>;
}

/** In-process sequential queue. Task errors are logged, never thrown. autoRun:false lets tests drain by hand. */
export function createTaskQueue(logger: Logger, autoRun = true): TaskQueue {
  const tasks: { name: string; fn: () => Promise<void> | void }[] = [];
  let current: Promise<void> | null = null;
  let scheduled = false;

  const pump = async () => {
    while (tasks.length) {
      const t = tasks.shift()!;
      try {
        await t.fn();
      } catch (e) {
        logger.error(`[queue] task "${t.name}" failed: ${(e as Error).message}`);
      }
    }
  };
  const start = () => {
    if (!current) current = pump().finally(() => (current = null));
    return current;
  };

  return {
    enqueue(name, fn) {
      tasks.push({ name, fn });
      if (autoRun && !scheduled && !current) {
        scheduled = true;
        setImmediate(() => {
          scheduled = false;
          void start();
        });
      }
    },
    async drain() {
      while (tasks.length || current) await start();
    },
  };
}
