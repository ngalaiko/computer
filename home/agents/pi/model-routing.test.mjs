import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import modelRouting from "./model-routing.ts";

const models = [
  ["openai-codex", "gpt-6-luna"],
  ["openai-codex", "gpt-6.1-sol"],
  ["openai-codex", "gpt-6-astra"],
  ["anthropic", "claude-haiku-5-5"],
  ["anthropic", "claude-sonnet-5-5"],
  ["anthropic", "claude-opus-5-5"],
].map(([provider, id]) => ({ provider, id, api: "test" }));

function harness(t, directory, available = models) {
  directory ??= mkdtempSync(join(tmpdir(), "pi-routing-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const routes = new Map();
  const handlers = new Map();
  const commands = new Map();
  const notifications = [];
  let now = 1_000_000;
  const pi = {
    registerVirtualModel(model) {
      routes.set(model.id, model);
    },
    registerCommand(name, command) {
      commands.set(name, command);
    },
    on(name, handler) {
      handlers.set(name, handler);
    },
    async setModel(model) {
      ctx.model = model;
      return true;
    },
  };
  const ctx = {
    model: { provider: "tiered", id: "main", api: "pi-virtual" },
    modelRegistry: {
      getAvailable: () => available,
      find: (provider, id) =>
        models.find((m) => m.provider === provider && m.id === id) ??
        (provider === "tiered"
          ? { provider, id, api: "pi-virtual" }
          : undefined),
    },
    ui: { notify: (...args) => notifications.push(args) },
  };
  modelRouting(pi, { directory, now: () => now });
  return {
    directory,
    routes,
    ctx,
    notifications,
    advance(ms) {
      now += ms;
    },
    route(tier, overrides = {}) {
      return routes.get(tier).route(
        {
          reason: "user",
          thinkingLevel: "medium",
          messages: [],
          ...overrides,
        },
        ctx,
      );
    },
    fail(provider, errorMessage, extra = {}) {
      return handlers.get("turn_end")(
        {
          entries: [],
          messageEntryId: "failed-response",
          toolResults: [],
          message: {
            role: "assistant",
            provider,
            stopReason: "error",
            errorMessage,
            content: [],
            ...extra,
          },
        },
        ctx,
      );
    },
    settle(outcome = "error", entries = []) {
      return handlers.get("agent_before_settle")({ entries, outcome }, ctx);
    },
    command(arg) {
      return commands.get("agent-tier").handler(arg, ctx);
    },
  };
}

function id(result) {
  return `${result.model.provider}/${result.model.id}`;
}

test("registers mixed tiers and preserves selected effort", (t) => {
  const h = harness(t);
  assert.equal(id(h.route("main")), "openai-codex/gpt-6.1-sol");
  assert.equal(id(h.route("worker")), "openai-codex/gpt-6.1-sol");
  assert.equal(id(h.route("scout")), "openai-codex/gpt-6-luna");
  assert.equal(id(h.route("reviewer")), "anthropic/claude-opus-5-5");
  assert.equal(id(h.route("oracle")), "openai-codex/gpt-6-astra");
  assert.equal(
    h.route("main", { thinkingLevel: "high" }).thinkingLevel,
    "high",
  );
});

test("OpenAI quota switches every tier to Claude across processes", (t) => {
  const h = harness(t);
  h.fail(
    "openai-codex",
    "You have hit your ChatGPT usage limit. Try again in ~120 min.",
  );
  const other = harness(t, h.directory);
  assert.equal(id(other.route("main")), "anthropic/claude-opus-5-5");
  assert.equal(id(other.route("worker")), "anthropic/claude-sonnet-5-5");
  assert.equal(id(other.route("scout")), "anthropic/claude-haiku-5-5");
  assert.equal(id(other.route("reviewer")), "anthropic/claude-opus-5-5");
  assert.equal(id(other.route("oracle")), "anthropic/claude-opus-5-5");
  assert.deepEqual(h.settle(), {
    entries: [
      { type: "context_edit", targetId: "failed-response", replacement: null },
    ],
    continue: true,
  });
  assert.equal(h.settle(), undefined);
  h.advance(121 * 60_000);
  assert.equal(id(h.route("main")), "openai-codex/gpt-6.1-sol");
});

test("Claude limits switch every tier to OpenAI", (t) => {
  const h = harness(t);
  h.fail("anthropic", "429 rate_limit_error: too many requests");
  for (const tier of h.routes.keys())
    assert.equal(h.route(tier).model.provider, "openai-codex");
  assert.equal(id(h.route("reviewer")), "openai-codex/gpt-6.1-sol");
  h.advance(6 * 60_000);
  assert.equal(id(h.route("reviewer")), "anthropic/claude-opus-5-5");
});

test("both providers exhausted stops rather than bouncing", (t) => {
  const h = harness(t);
  h.fail("openai-codex", "insufficient_quota");
  h.fail("anthropic", "Usage limit reached");
  assert.equal(h.settle(), undefined);
  assert.throws(() => h.route("main"), /No available provider/);
});

test("auth, transport, context, and server errors do not cause failover", (t) => {
  for (const error of [
    "401 Unauthorized",
    "fetch failed",
    "503 overloaded",
    "context length exceeded",
    "invalid API key",
  ]) {
    const h = harness(t);
    h.fail("openai-codex", error);
    assert.equal(h.settle(), undefined);
    assert.equal(id(h.route("main")), "openai-codex/gpt-6.1-sol");
  }
});

test("cancelled responses and physical model selections are untouched", (t) => {
  const h = harness(t);
  h.fail("openai-codex", "rate limit", { stopReason: "aborted" });
  assert.equal(h.settle(), undefined);
  h.ctx.model = models[1];
  h.fail("openai-codex", "rate limit");
  assert.equal(h.settle(), undefined);
  assert.equal(id(h.route("main")), "openai-codex/gpt-6.1-sol");
});

test("never automatically replays a response containing tool calls", (t) => {
  const h = harness(t);
  h.fail("openai-codex", "rate limit", {
    content: [{ type: "toolCall", name: "write" }],
  });
  assert.equal(h.settle(), undefined);
  assert.throws(
    () =>
      h.route("main", {
        reason: "retry",
        failed: {
          message: {
            errorMessage: "rate limit",
            content: [{ type: "toolCall" }],
          },
        },
      }),
    /inspection/,
  );
  assert.equal(h.route("main").model.provider, "anthropic");
});

test("cancellation and subsequent responses clear pending recovery", (t) => {
  const h = harness(t);
  h.fail("openai-codex", "quota exceeded");
  assert.equal(h.settle("aborted"), undefined);
  h.fail("anthropic", "not a quota error");
  assert.equal(h.settle("completed"), undefined);
});

test("manual provider-only modes never cross providers", async (t) => {
  const h = harness(t);
  await h.command("openai");
  for (const tier of h.routes.keys())
    assert.equal(h.route(tier).model.provider, "openai-codex");
  h.fail("openai-codex", "quota exceeded");
  assert.equal(h.settle(), undefined);
  assert.throws(() => h.route("main"), /No available provider/);
  await h.command("claude");
  for (const tier of h.routes.keys())
    assert.equal(h.route(tier).model.provider, "anthropic");
  await h.command("reset");
  await h.command("mixed");
  assert.equal(id(h.route("main")), "openai-codex/gpt-6.1-sol");
});

test("missing credentials use the remaining provider; missing models fail", (t) => {
  const h = harness(
    t,
    undefined,
    models.filter((m) => m.provider === "anthropic"),
  );
  assert.equal(h.route("main").model.provider, "anthropic");
  const empty = harness(t, undefined, []);
  assert.throws(() => empty.route("main"), /No available provider/);
});

test("failed continuation preserves earlier extension entries", (t) => {
  const h = harness(t);
  h.fail("openai-codex", "quota exceeded");
  const entry = { type: "custom", customType: "other-extension", data: {} };
  assert.deepEqual(h.settle("error", [entry]).entries, [
    entry,
    { type: "context_edit", targetId: "failed-response", replacement: null },
  ]);
});

test("recognizes provider quota wording without an HTTP status", (t) => {
  for (const error of [
    "You exceeded your current quota, please check your plan and billing details.",
    "Your credit balance is too low to access the Anthropic API.",
    "subscription_sharing_usage_limit_exceeded",
    "usage_limit_reached",
  ]) {
    const h = harness(t);
    h.fail("openai-codex", error);
    assert.equal(h.route("main").model.provider, "anthropic", error);
  }
});

test("invalid commands do not change routing", async (t) => {
  const h = harness(t);
  await h.command("typo");
  assert.equal(id(h.route("reviewer")), "anthropic/claude-opus-5-5");
  assert.match(h.notifications.at(-1)[0], /mixed.*openai.*claude/);
});
