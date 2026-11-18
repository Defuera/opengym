import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

/** Erases sessions and notes that were marked as deleted more than 72 hours ago (ADR-020). */
crons.interval("purge deleted", { hours: 1 }, internal.jobs.purge.run, {});

export default crons;
