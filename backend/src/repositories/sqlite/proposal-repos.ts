import type { Database } from "better-sqlite3";
import type { DashboardSpec, ImportJob, Plan, Prediction } from "../../schema";
import type {
  DashboardSpecRepository,
  ImportRepository,
  PlanRepository,
  PredictionRepository,
} from "../types";
import { DocStore, KvStore } from "./doc-store";

export class SqlitePlanRepository implements PlanRepository {
  private readonly kv: KvStore<Plan>;
  constructor(db: Database) {
    this.kv = new KvStore<Plan>(db, "plans");
  }
  get(type: string) {
    return this.kv.get(type);
  }
  put(p: Plan) {
    this.kv.put(p.type, p);
    return p;
  }
  clear() {
    this.kv.clear();
  }
}

export class SqliteDashboardSpecRepository implements DashboardSpecRepository {
  private readonly kv: KvStore<DashboardSpec>;
  constructor(db: Database) {
    this.kv = new KvStore<DashboardSpec>(db, "dashboard_specs");
  }
  get(days: number) {
    return this.kv.get(String(days));
  }
  put(days: number, spec: DashboardSpec) {
    this.kv.put(String(days), spec);
  }
  clear() {
    this.kv.clear();
  }
}

export class SqlitePredictionRepository implements PredictionRepository {
  private readonly kv: KvStore<Prediction[]>;
  constructor(db: Database) {
    this.kv = new KvStore<Prediction[]>(db, "predictions");
  }
  get() {
    return this.kv.get("main");
  }
  put(p: Prediction[]) {
    this.kv.put("main", p);
  }
  clear() {
    this.kv.clear();
  }
}

export class SqliteImportRepository implements ImportRepository {
  private readonly store: DocStore<ImportJob>;
  constructor(db: Database) {
    this.store = new DocStore<ImportJob>(
      db,
      "imports",
      { created_at: { type: "INTEGER", get: (j) => j.createdAt } },
      "created_at DESC, rowid DESC",
    );
  }
  put(j: ImportJob) {
    return this.store.put(j);
  }
  get(id: string) {
    return this.store.get(id);
  }
  list() {
    return this.store.list();
  }
  delete(id: string) {
    return this.store.delete(id);
  }
}
