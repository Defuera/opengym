export const DAY_MS = 86_400_000;

export function fmtKg(k: number): string {
  const r = Math.round(k * 10) / 10;
  return Number.isInteger(r) ? String(r) : String(r);
}

/** UTC calendar-day key. The server has no user time zone. */
export function dayKey(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

export function whenLabel(t: number, now: number): string {
  const d = Math.floor((Date.parse(dayKey(now)) - Date.parse(dayKey(t))) / DAY_MS);
  if (d <= 0) return "Today";
  if (d === 1) return "Yesterday";
  return `${d} days ago`;
}

export function truncate(s: string, n: number): string {
  return s.length <= n ? s : `${s.slice(0, Math.max(0, n - 1)).trimEnd()}…`;
}
