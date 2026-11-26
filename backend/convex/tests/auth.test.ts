import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { api } from "../functions/_generated/api";
import { requireUser } from "../functions/lib/auth";
import { TOKEN, setup, type T } from "./helpers";
import { TOKEN_B, USER_A, USER_B } from "./multiUser";

/** ADR-039: the one place that turns a token into a user. */
let t: T;
beforeEach(() => {
  t = setup();
});
afterEach(() => {
  vi.unstubAllEnvs();
});

describe("requireUser", () => {
  it("maps the app token to the owner", async () => {
    expect(await requireUser({}, TOKEN)).toBe(USER_A);
  });

  it("refuses an unknown token, an empty token and a missing app token", async () => {
    await expect(requireUser({}, "nope")).rejects.toThrow("unauthorized");
    await expect(requireUser({}, "")).rejects.toThrow("unauthorized");
    vi.stubEnv("APP_TOKEN", "");
    await expect(requireUser({}, TOKEN)).rejects.toThrow("unauthorized");
    await expect(requireUser({}, "")).rejects.toThrow("unauthorized");
  });

  it("has no second user unless the test-only map is set: a token of a second user is refused", async () => {
    await expect(requireUser({}, TOKEN_B)).rejects.toThrow("unauthorized");
    await expect(t.query(api.queries.goals.list, { token: TOKEN_B })).rejects.toThrow("unauthorized");
    await expect(t.mutation(api.commands.goals.create, { token: TOKEN_B, goalId: "g", title: "x", kind: "custom" })).rejects.toThrow("unauthorized");
  });

  it("the test-only map adds users, and cannot take over the owner or accept an empty token", async () => {
    vi.stubEnv("APP_EXTRA_TOKENS", JSON.stringify({ [TOKEN_B]: USER_B, [TOKEN]: "thief", "": "empty", other: "" }));
    expect(await requireUser({}, TOKEN_B)).toBe(USER_B);
    expect(await requireUser({}, TOKEN)).toBe(USER_A);
    await expect(requireUser({}, "")).rejects.toThrow("unauthorized");
    await expect(requireUser({}, "other")).rejects.toThrow("unauthorized");
    vi.stubEnv("APP_EXTRA_TOKENS", "not json");
    await expect(requireUser({}, TOKEN_B)).rejects.toThrow("unauthorized");
    vi.stubEnv("APP_EXTRA_TOKENS", "[1]");
    await expect(requireUser({}, TOKEN_B)).rejects.toThrow("unauthorized");
  });

  it("every public function refuses a bad token", async () => {
    await expect(t.query(api.queries.sessions.recent, { token: "bad" })).rejects.toThrow("unauthorized");
    await expect(t.mutation(api.commands.sessions.remove, { token: "bad", sessionId: "s" })).rejects.toThrow("unauthorized");
    await expect(t.action(api.commands.voice.transcribe, { token: "bad", fileId: "f" })).rejects.toThrow("unauthorized");
  });
});
