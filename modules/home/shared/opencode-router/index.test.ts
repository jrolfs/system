import assert from "node:assert/strict";
import { test } from "node:test";
import { parseOptions, routeTask, shouldRoute } from "./index.ts";

const options = parseOptions({
  apiKeyFile: "/unused/key",
  model: "jev-latest",
  candidates: [
    { model: "openai/fast", description: "Straightforward tasks" },
    { model: "anthropic/strong", description: "Complex tasks" },
  ],
  fallbackModel: "anthropic/strong",
  minConfidence: 0.8,
  timeoutMs: 1_000,
});
const task = { agent: "explore", prompt: "Find the configuration entry point" };
const available = new Set(options.candidates.map((candidate) => candidate.model));
const answer = (overrides: Record<string, unknown> = {}): Response => Response.json({
  answers: { route: { type: "choice", choice: "openai/fast", confidence: 0.95,
    probabilities: { "openai/fast": 0.9, "anthropic/strong": 0.1 }, ...overrides } },
});

test("routes new built-in delegations only, preserving explicit models and resumed sessions", () => {
  assert.equal(shouldRoute("subagent", task), true);
  assert.equal(shouldRoute("subagent", { ...task, agent: "general" }), true);
  for (const input of [null, {}, { ...task, model: "provider/explicit" },
    { ...task, sessionID: "ses_existing" }, { ...task, agent: "specialist" }]) {
    assert.equal(shouldRoute("subagent", input), false);
  }
  assert.equal(shouldRoute("shell", task), false);
});

test("uses a valid confident Jev choice", async () => {
  const selection = await routeTask({ options, task, available, readKey: async () => "test-key\n",
    fetcher: async (url, request) => {
      assert.equal(url, "https://api.typesafe.ai/v1/systemone");
      assert.equal(request?.redirect, "error");
      assert.equal((request?.headers as Record<string, string>).Authorization, "Bearer test-key");
      const body = JSON.parse(String(request?.body));
      assert.deepEqual(body.state, task);
      assert.deepEqual(Object.keys(body.questions.route.criteria), [...available]);
      return answer();
    } });
  assert.equal(selection.model, "openai/fast");
});

test("uses the strong fallback for uncertain or malformed choices", async () => {
  for (const overrides of [{ confidence: 0.5 }, { confidence: 2 }, { choice: "outside/model" },
    { probabilities: { "openai/fast": 0.1, "anthropic/strong": 0.9 } },
    { probabilities: { "openai/fast": 0.8 } },
    { probabilities: { "openai/fast": 0.9, "anthropic/strong": 0.9 } }]) {
    const selection = await routeTask({ options, task, available, readKey: async () => "test-key",
      fetcher: async () => answer(overrides) });
    assert.equal(selection.model, "anthropic/strong");
  }
});

test("uses the fallback on provider, credential, and response failures", async () => {
  for (const fetcher of [async () => { throw new Error("offline"); },
    async () => new Response("unavailable", { status: 503 }),
    async () => new Response("invalid JSON"),
    async () => new Response("x".repeat(70_000))]) {
    const selection = await routeTask({ options, task, available, readKey: async () => "test-key", fetcher });
    assert.equal(selection.model, "anthropic/strong");
  }
  const selection = await routeTask({ options, task, available,
    readKey: async () => { throw new Error("missing key"); },
    fetcher: async () => { throw new Error("must not fetch"); } });
  assert.equal(selection.model, "anthropic/strong");
});

test("never calls Jev for zero or one eligible models", async () => {
  const fetcher = async (): Promise<Response> => { throw new Error("must not fetch"); };
  assert.equal((await routeTask({ options, task, available: new Set(), fetcher })).model, undefined);
  assert.equal((await routeTask({ options, task, available: new Set(["openai/fast"]), fetcher })).model, "openai/fast");
});

test("does not truncate an oversized task before deciding its capability needs", async () => {
  const selection = await routeTask({ options, task: { ...task, prompt: "x".repeat(50_000) }, available,
    fetcher: async () => { throw new Error("must not fetch"); } });
  assert.equal(selection.model, "anthropic/strong");
  assert.match(selection.reason, /too large/);
});

test("validates the candidate pool and fallback", () => {
  for (const overrides of [{ candidates: [] }, { candidates: [options.candidates[0], options.candidates[0]] },
    { fallbackModel: "outside/model" }, { minConfidence: -1 }, { timeoutMs: 0 }, { apiKeyFile: "relative/key" }]) {
    assert.throws(() => parseOptions({ ...options, ...overrides }));
  }
});
