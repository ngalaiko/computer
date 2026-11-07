import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import test from "node:test";
import { registerFeatureStatus } from "./feature-status/status.mjs";

const Type = {
  Object: (properties) => ({ type: "object", properties }),
  String: (options) => ({ type: "string", ...options }),
  Literal: (value) => ({ const: value }),
  Union: (anyOf) => ({ anyOf }),
  Optional: (value) => value,
};
const context = { mode: "tui" };
function harness(available = true, name = "exports: review") {
  const writes = [];
  const handlers = new Map();
  let tool;
  registerFeatureStatus(
    {
      registerTool(value) {
        tool = value;
      },
      on(event, fn) {
        handlers.set(event, fn);
      },
      getSessionName: () => name,
    },
    Type,
    {
      available: (ctx) => available && ctx.mode === "tui",
      write: (value) => writes.push(value),
    },
  );
  return {
    tool,
    writes,
    handlers,
    execute: (args) =>
      tool.execute("call", args, undefined, undefined, context),
  };
}
function decode(sequence) {
  assert.ok(sequence.startsWith("\u001b]7501;"));
  assert.ok(sequence.endsWith("\u001b\\"));
  return Object.fromEntries(
    sequence
      .slice(7, -2)
      .split(":")
      .map((pair) => {
        const i = pair.indexOf("=");
        const key = pair.slice(0, i),
          value = pair.slice(i + 1);
        return [
          key,
          ["msg", "title"].includes(key)
            ? Buffer.from(value, "base64").toString("utf8")
            : value,
        ];
      }),
  );
}

test("feature milestones use their own OSC record without replacing native Pi status", async () => {
  const h = harness();
  await h.execute({ phase: "review-ready", message: "Impact summary ready" });
  assert.deepEqual(decode(h.writes[0]), {
    id: "feature",
    state: "done",
    app: "pi",
    title: "exports: review",
    msg: "Impact summary ready",
  });
});

test("maps feature phases to native status states and blocked kinds", async () => {
  const h = harness();
  for (const [phase, state, kind] of [
    ["implementing", "working"],
    ["testing", "working"],
    ["reviewing", "working"],
    ["review-ready", "done"],
    ["question", "blocked", "question"],
    ["approval", "blocked", "permission"],
    ["auth", "blocked", "auth"],
    ["failed", "error"],
    ["awaiting-merge", "idle"],
    ["complete", "done"],
  ]) {
    await h.execute({ phase });
    const record = decode(h.writes.at(-1));
    assert.equal(record.state, state, phase);
    assert.equal(record.kind, kind, phase);
    assert.ok(record.msg);
    assert.equal(record.id, "feature");
  }
});

test("deduplicates identical reports but republishes after clearing", async () => {
  const h = harness();
  await h.execute({ phase: "question", message: "Which retention period?" });
  await h.execute({ phase: "question", message: "Which retention period?" });
  assert.equal(h.writes.length, 1);
  await h.execute({ phase: "clear" });
  assert.deepEqual(decode(h.writes.at(-1)), { id: "feature", state: "clear" });
  await h.execute({ phase: "question", message: "Which retention period?" });
  assert.equal(h.writes.length, 3);
});

test("clears only owned feature status on work, navigation, reload and shutdown", async () => {
  const h = harness();
  for (const event of [
    "agent_start",
    "session_tree",
    "session_start",
    "session_shutdown",
  ]) {
    await h.execute({ phase: "approval" });
    assert.ok(h.handlers.has(event), event);
    await h.handlers.get(event)({}, context);
    assert.deepEqual(decode(h.writes.at(-1)), {
      id: "feature",
      state: "clear",
    });
  }
});

test("clears a cancelled run without clearing normally settled milestones", async () => {
  const h = harness();
  await h.execute({ phase: "review-ready" });
  await h.handlers.get("agent_settled")({ aborted: false }, context);
  assert.equal(h.writes.length, 1);
  await h.handlers.get("agent_settled")({ aborted: true }, context);
  assert.deepEqual(decode(h.writes.at(-1)), { id: "feature", state: "clear" });
});

test("bounds and sanitizes native Pi names without breaking UTF-8", async () => {
  const h = harness(true, "exports\n\u001b: " + "🦋".repeat(100));
  await h.execute({ phase: "testing" });
  const record = decode(h.writes[0]);
  assert.ok(Buffer.byteLength(record.title, "utf8") <= 192);
  assert.doesNotMatch(record.title, /[\u0000-\u001f\ufffd]/u);
  assert.ok(Buffer.byteLength(h.writes[0], "utf8") < 4096);
});

test("rejects malformed phases, control text and oversized UTF-8 before output", async () => {
  const h = harness();
  for (const args of [
    { phase: "bogus" },
    { phase: "question", message: "" },
    { phase: "question", message: "\u001b]9;spoof\u0007" },
    { phase: "question", message: "line\nline" },
    { phase: "failed", message: "é".repeat(300) },
  ])
    await assert.rejects(() => h.execute(args));
  assert.deepEqual(h.writes, []);
});

test("does not emit terminal control bytes outside interactive Rex", async () => {
  const h = harness(false);
  await assert.rejects(
    () => h.execute({ phase: "review-ready" }),
    /unavailable/i,
  );
  for (const handler of h.handlers.values())
    await handler({}, { mode: "json" });
  assert.deepEqual(h.writes, []);
});

test("production guards require TUI, a TTY and both Rex context IDs", () => {
  for (const [mode, tty, session, block, allowed] of [
    ["tui", true, "session:test", "block:test", true],
    ["json", true, "session:test", "block:test", false],
    ["rpc", true, "session:test", "block:test", false],
    ["tui", false, "session:test", "block:test", false],
    ["tui", true, "", "block:test", false],
    ["tui", true, "session:test", "", false],
  ]) {
    const source = `
      import { registerFeatureStatus } from ${JSON.stringify(new URL("./feature-status/status.mjs", import.meta.url).href)};
      const Type = { Object: x => x, String: x => x, Literal: x => x, Union: x => x, Optional: x => x };
      Object.defineProperty(process.stdout, "isTTY", { value: ${tty} });
      let tool;
      registerFeatureStatus({ registerTool: value => tool = value, on() {}, getSessionName: () => "Test" }, Type);
      try { await tool.execute("call", { phase: "testing" }, undefined, undefined, { mode: ${JSON.stringify(mode)} }); }
      catch (error) { process.stdout.write(error.message); }
    `;
    const output = execFileSync(
      process.execPath,
      ["--input-type=module", "-e", source],
      {
        encoding: "utf8",
        env: { ...process.env, REX_SESSION: session, REX_BLOCK: block },
      },
    );
    assert.equal(output.startsWith("\u001b]7501;id=feature:"), allowed);
    if (!allowed) assert.match(output, /unavailable/i);
  }
});

test("does not claim Rex reception or notification delivery", async () => {
  const h = harness();
  const result = await h.execute({ phase: "review-ready" });
  assert.equal(result.details.emitted, true);
  assert.match(result.content[0].text, /verify.*program_status/i);
});

test("deploys to parents and has a Nix check", () => {
  const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
  assert.match(
    read("../pi.nix"),
    /"\.pi\/agent\/extensions\/feature-status"\.source = \.\/pi\/feature-status/,
  );
  assert.match(read("../../../flake.nix"), /feature-status\.test\.mjs/);
});
