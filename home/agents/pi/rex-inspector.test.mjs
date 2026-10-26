import assert from "node:assert/strict";
import test from "node:test";
import rexInspector from "./rex-inspector.ts";

function setup(t, { inRex = true, result, register = true } = {}) {
  const saved = { ...process.env };
  t.after(() => {
    process.env = saved;
  });
  delete process.env.REX_SESSION;
  delete process.env.REX_BLOCK;
  if (inRex) {
    process.env.REX_SESSION = "session:parent";
    process.env.REX_BLOCK = "block:parent";
  }
  const handlers = {};
  const calls = [];
  let plugin;
  let disposed = 0;
  rexInspector({
    on(event, handler) {
      handlers[event] = handler;
    },
    events: {
      emit(event, request) {
        assert.equal(event, "pi-subagents:inspector-register:v1");
        assert.equal(request.version, 1);
        plugin = request.plugin;
        if (register) {
          request.result = {
            ok: true,
            registration: { dispose: () => disposed++ },
          };
        }
      },
    },
    async exec(...args) {
      calls.push(args);
      return result ?? { code: 0, stdout: '{"block_ids":["block:inspector"]}', stderr: "" };
    },
  });
  return {
    handlers,
    calls,
    get plugin() { return plugin; },
    get disposed() { return disposed; },
  };
}

const context = {
  cwd: "/parent repo",
  env: { REX_SESSION: "session:parent", REX_BLOCK: "block:parent" },
  target: { runId: "run-1", status: { cwd: "/child repo", state: "running" } },
};
const launch = {
  executable: "/path with spaces/node",
  argv: ["/inspector runner.mjs", "--index", "2", "--allow-steer", "literal;$(value)"],
};

test("opens the supplied inspector beside Pi without a shell or focus change", async (t) => {
  const fixture = setup(t);
  fixture.handlers.session_start();
  assert.equal(fixture.plugin.name, "rex");
  assert.equal(fixture.plugin.available(context), true);
  assert.equal(fixture.plugin.available({ env: {} }), false);
  assert.equal(fixture.plugin.available({ env: { REX_SESSION: "session:parent" } }), false);
  const result = await fixture.plugin.open(context, launch, {});
  assert.deepEqual(fixture.calls, [["rex", [
    "split", "-s", "session:parent", "-b", "block:parent", "--split=right",
    "--focus=false", "--shell=none", "--label", "Subagent inspector",
    "-c", "/child repo", "--json", "--", launch.executable, ...launch.argv,
  ], { cwd: "/parent repo", timeout: 15000 }]]);
  assert.match(result.content[0].text, /Opened/);
  assert.equal(fixture.plugin.owns(context), false);
});

test("honors explicit focus and falls back to the action working directory", async (t) => {
  const fixture = setup(t);
  fixture.handlers.session_start();
  await fixture.plugin.open({ ...context, target: { status: {} } }, launch, { focus: true });
  assert.ok(fixture.calls[0][1].includes("--focus=true"));
  const args = fixture.calls[0][1];
  assert.equal(args[args.indexOf("-c") + 1], "/parent repo");
});

test("surfaces Rex failures without retrying pane creation", async (t) => {
  const fixture = setup(t, { result: { code: 1, stdout: "", stderr: "pane not found" } });
  fixture.handlers.session_start();
  await assert.rejects(fixture.plugin.open(context, launch, {}), /pane not found/);
  assert.equal(fixture.calls.length, 1);
});

test("disposes registration on session replacement and shutdown", (t) => {
  const fixture = setup(t);
  fixture.handlers.session_start();
  fixture.handlers.session_start();
  assert.equal(fixture.disposed, 1);
  fixture.handlers.session_shutdown();
  fixture.handlers.session_shutdown();
  assert.equal(fixture.disposed, 2);
});

test("does not register outside Rex", (t) => {
  const fixture = setup(t, { inRex: false });
  fixture.handlers.session_start();
  assert.equal(fixture.plugin, undefined);
});

test("reports an unavailable registration API", (t) => {
  const fixture = setup(t, { register: false });
  assert.throws(() => fixture.handlers.session_start(), /registration is unavailable/);
});
