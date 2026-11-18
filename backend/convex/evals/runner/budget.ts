/** A hard cap on provider calls (retries count). When it is spent, `take` says no and the run stops. */
export class Budget {
  used = 0;
  constructor(readonly max: number) {}

  get spent(): boolean {
    return this.used >= this.max;
  }

  take(): boolean {
    if (this.used >= this.max) return false;
    this.used++;
    return true;
  }
}

export const BUDGET_ERROR = "BudgetExceeded: the --max-calls budget is spent";
