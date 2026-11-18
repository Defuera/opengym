/** Rules every system prompt carries. */
export const COMMON_RULES = `Never invent logged data. Use only the data provided to you for what the person did; if something is not in the data, say it is not known.`;

/** One sentence for every job that plans or advises training. The data may hold `limits`. */
export const LIMITS_RULE = "The data may list limits (body parts the user trains around): never use a movement a rule marks avoid, keep load light where a rule says light, and prefer what a do rule names.";

export const JSON_ONLY = "Reply with JSON only (no prose, no code fences) matching exactly this shape:";

/** The mock provider reads the JOB line to pick its canned answer. */
export function systemPrompt(job: string, role: string, shape?: string): string {
  const parts = [`JOB: ${job}`, role, COMMON_RULES];
  if (shape) parts.push(`${JSON_ONLY}\n${shape}`);
  return parts.join("\n\n");
}

/** User turn for data-driven jobs; the mock reads INPUT_JSON. */
export function dataPrompt(instruction: string, data: unknown): string {
  return `${instruction}\n\nINPUT_JSON:\n${JSON.stringify(data)}`;
}
