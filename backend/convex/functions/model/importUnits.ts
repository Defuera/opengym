import type { ImportSessionDraft, Session } from "./schema";
import { SessionSchema } from "./schema";

/** Draft session from the import job -> a validated session, or null with a note. Port of import-runner toSession. */
export function draftToSession(d: ImportSessionDraft, file: { name: string; createdAt: number }, importId: string, newId: () => string, notes: Set<string>): Session | null {
  let at = d.date ? Date.parse(d.date) : NaN;
  if (Number.isNaN(at)) {
    at = file.createdAt;
    notes.add(`${file.name}: no date found for some sessions, used the file's upload time (${new Date(file.createdAt).toISOString()}).`);
  }
  const parsed = SessionSchema.safeParse({
    id: newId(),
    kind: d.kind,
    type: d.type,
    startedAt: at - (d.minutes ?? 0) * 60_000,
    endedAt: at,
    exercises: d.kind === "gym" ? d.exercises : [],
    minutes: d.minutes,
    distanceKm: d.distanceKm,
    note: d.note,
    source: "import",
    importId,
  });
  if (!parsed.success) {
    notes.add(`${file.name}: skipped a session that did not validate (${parsed.error.issues[0]?.message}).`);
    return null;
  }
  return parsed.data;
}
