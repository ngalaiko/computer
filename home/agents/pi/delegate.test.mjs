import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import test from "node:test";
import delegate from "./delegate.ts";

const fixture = fileURLToPath(
  new URL("./fixtures/delegate-child.mjs", import.meta.url),
);

async function waitForFile(file) {
  for (let attempt = 0; attempt < 100; attempt++) {
    if (existsSync(file)) return;
    await delay(20);
  }
  throw new Error(`Child did not start: ${file}`);
}

function setup(t, { colocate = false } = {}) {
  const directory = realpathSync(mkdtempSync(join(tmpdir(), "pi-delegate-")));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const repo = join(directory, "repo");
  const jj = (args, cwd = repo) =>
    execFileSync(
      "jj",
      [
        "--color",
        "never",
        "--no-pager",
        "--config",
        "user.name=Test",
        "--config",
        "user.email=test@example.invalid",
        ...args,
      ],
      { cwd: args[0] === "git" ? directory : cwd, encoding: "utf8" },
    ).trim();
  jj(["git", "init", colocate ? "--colocate" : "--no-colocate", repo]);
  writeFileSync(join(repo, "source.txt"), "parent content\n");
  let tool;
  const handlers = {};
  delegate(
    {
      registerTool(value) {
        tool = value;
      },
      on(event, handler) {
        handlers[event] = handler;
      },
    },
    {
      directory: join(directory, "delegations"),
      invocation: { command: process.execPath, args: [fixture] },
    },
  );
  const call = (task, params = {}, signal, onUpdate) =>
    tool.execute(
      "call",
      { task: JSON.stringify(task), ...params },
      signal,
      onUpdate,
      { cwd: repo, isProjectTrusted: () => true },
    );
  return {
    directory,
    repo,
    jj,
    call,
    handlers,
    get tool() {
      return tool;
    },
  };
}

test("worker inherits the current JJ files without changing the parent", async (t) => {
  const h = setup(t, { colocate: true });
  const parent = h.jj(["log", "--no-graph", "-r", "@", "-T", "change_id"]);
  const result = await h.call({
    inspect: "source.txt",
    file: "source.txt",
    content: "worker content\n",
  });
  assert.notEqual(result.isError, true);
  const child = JSON.parse(result.details.output);
  assert.equal(child.model, "openai-codex/gpt-6.1-sol");
  assert.equal(child.thinking, "medium");
  assert.equal(child.baseContent, "parent content\n");
  assert.equal(child.cwd, result.details.workspace);
  assert.equal(existsSync(join(result.details.workspace, ".git")), false);
  assert.equal(
    readFileSync(join(h.repo, "source.txt"), "utf8"),
    "parent content\n",
  );
  assert.equal(
    readFileSync(join(result.details.workspace, "source.txt"), "utf8"),
    "worker content\n",
  );
  assert.equal(
    h.jj(["log", "--no-graph", "-r", "@", "-T", "change_id"]),
    parent,
  );
  assert.match(
    h.jj(["workspace", "list"]),
    new RegExp(result.details.workspaceName),
  );
  assert.match(result.details.changeId, /^[k-z]+$/);
  assert.match(readFileSync(result.details.resultPath, "utf8"), /worker/);
  assert.equal(result.usage.totalTokens, 35);
});

test("roles pin models; reviews use read-only tools without a workspace", async (t) => {
  const h = setup(t);
  const small = await h.call({}, { role: "small-worker" });
  assert.notEqual(small.isError, true, small.content[0].text);
  const worker = JSON.parse(small.details.output);
  assert.equal(worker.model, "openai-codex/gpt-6.1-terra");
  assert.equal(worker.thinking, "medium");
  assert.match(worker.args.join(" "), /--no-extensions.*--no-mcp/);
  assert.match(worker.args.join(" "), /--extension .*command-guards.ts/);
  const bridgePath = join(homedir(), ".pi", "agent", "npm", "node_modules", "claude-code-pi");
  assert.ok(!worker.args.includes(bridgePath));
  const before = h.jj(["workspace", "list"]);
  const review = await h.call(
    {},
    { role: "reviewer", cwd: small.details.workspace },
  );
  assert.notEqual(review.isError, true, review.content[0].text);
  const reviewer = JSON.parse(review.details.output);
  assert.equal(reviewer.model, "claude-code-cli/opus");
  const bridge = reviewer.args.indexOf(bridgePath);
  assert.ok(bridge > 0);
  assert.equal(reviewer.args[bridge - 1], "--extension");
  assert.equal(reviewer.thinking, "high");
  assert.equal(reviewer.tools, "read,grep,find,ls");
  assert.equal(reviewer.cwd, small.details.workspace);
  assert.equal(review.details.workspace, undefined);
  assert.doesNotMatch(review.content[0].text, /undefined/);
  assert.match(reviewer.prompt, /diff.patch/);
  assert.equal(h.jj(["workspace", "list"]), before);
});

test("provider and process failures retain work, diagnostics, and usage", async (t) => {
  const h = setup(t);
  const failed = await h.call({
    file: "partial.txt",
    content: "kept",
    error: "rate limited",
  });
  assert.equal(failed.isError, true);
  assert.match(failed.content[0].text, /rate limited/);
  assert.match(failed.details.output, /gpt-6.1-sol/);
  assert.equal(failed.usage.totalTokens, 35);
  assert.match(failed.details.changeId, /^[k-z]+$/);
  assert.equal(
    readFileSync(join(failed.details.workspace, "partial.txt"), "utf8"),
    "kept",
  );
  assert.match(
    h.jj(["workspace", "list"]),
    new RegExp(failed.details.workspaceName),
  );
  const crashed = await h.call({
    file: "partial.txt",
    content: "startup",
    exit: 7,
  });
  assert.equal(crashed.isError, true);
  assert.match(crashed.content[0].text, /child startup failed/);
  assert.equal(
    readFileSync(join(crashed.details.workspace, "partial.txt"), "utf8"),
    "startup",
  );
});

test("cancellation stops the child and retains its partial workspace", async (t) => {
  const h = setup(t);
  const ready = join(h.directory, "ready");
  const controller = new AbortController();
  const pending = h.call(
    { wait: true, ready, file: "partial.txt", content: "kept" },
    {},
    controller.signal,
  );
  await waitForFile(ready);
  const pid = Number(readFileSync(ready, "utf8"));
  t.after(() => {
    try {
      process.kill(pid, "SIGKILL");
    } catch {}
  });
  controller.abort();
  const result = await Promise.race([
    pending,
    delay(2000).then(() => {
      throw new Error("Cancellation did not stop the child");
    }),
  ]);
  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /cancel/i);
  assert.equal(
    readFileSync(join(result.details.workspace, "partial.txt"), "utf8"),
    "kept",
  );
  assert.match(
    h.jj(["workspace", "list"]),
    new RegExp(result.details.workspaceName),
  );
  assert.throws(() => process.kill(pid, 0), /ESRCH/);
  assert.notEqual((await h.call({})).isError, true);
});

test("two delegates run concurrently; shutdown cancels them and releases capacity", async (t) => {
  const h = setup(t);
  const controllers = [new AbortController(), new AbortController()];
  const files = [join(h.directory, "one"), join(h.directory, "two")];
  const pending = files.map((ready, index) =>
    h.call({ ready, wait: true }, {}, controllers[index].signal),
  );
  t.after(async () => {
    controllers.forEach((controller) => controller.abort());
    await Promise.allSettled(pending);
  });
  await Promise.all(files.map(waitForFile));
  await assert.rejects(h.call({}), /two delegates/i);
  await h.handlers.session_shutdown();
  const results = await Promise.all(pending);
  assert.ok(results.every((result) => result.isError));
  for (const file of files) {
    assert.throws(
      () => process.kill(Number(readFileSync(file, "utf8")), 0),
      /ESRCH/,
    );
  }
  await assert.rejects(h.call({}), /shut down/i);
});

test("reports usage across child turns without counting agent_end replays", async (t) => {
  const h = setup(t);
  const result = await h.call({ multi: true });
  assert.notEqual(result.isError, true);
  assert.equal(result.usage.input, 20);
  assert.equal(result.usage.output, 10);
  assert.equal(result.usage.cacheRead, 40);
  assert.equal(result.usage.totalTokens, 70);
  assert.equal(result.usage.cost.total, 0.062);
});

test("delegates from a package directory keep that directory in the workspace", async (t) => {
  const h = setup(t);
  mkdirSync(join(h.repo, "package"));
  writeFileSync(join(h.repo, "package", "input.txt"), "package input");
  const result = await h.call({ inspect: "input.txt" }, { cwd: "package" });
  assert.notEqual(result.isError, true, result.content[0].text);
  const child = JSON.parse(result.details.output);
  assert.equal(child.cwd, join(result.details.workspace, "package"));
  assert.equal(child.baseContent, "package input");
});

test("children cannot register another delegation tool", async (t) => {
  const h = setup(t);
  const result = await h.call({
    extension: new URL("./delegate.ts", import.meta.url).href,
  });
  assert.notEqual(result.isError, true, result.content[0].text);
  assert.deepEqual(JSON.parse(result.details.output).nestedTools, []);
});

test("invalid and already-cancelled requests create no artifacts or workspaces", async (t) => {
  const h = setup(t);
  await assert.rejects(
    h.call({}, { role: "unknown" }),
    /Unknown delegation role/,
  );
  await assert.rejects(h.call({}, { task: " " }), /Task must not be empty/);
  await assert.rejects(h.call({}, {}, AbortSignal.abort()), /abort/i);
  assert.equal(existsSync(join(h.directory, "delegations")), false);
  assert.equal(h.jj(["workspace", "list"]).split("\n").length, 1);
});

test("delegation does not grant parent project trust to an unrelated repository", async (t) => {
  const h = setup(t);
  const other = join(h.directory, "other");
  h.jj(["git", "init", "--no-colocate", other]);
  const result = await h.call({}, { role: "reviewer", cwd: other });
  assert.notEqual(result.isError, true, result.content[0].text);
  const child = JSON.parse(result.details.output);
  assert.ok(child.args.includes("--no-approve"));
  assert.ok(!child.args.includes("--approve"));
});

test("large reports stay on disk instead of flooding the parent context", async (t) => {
  const h = setup(t);
  const updates = [];
  const result = await h.call({ padding: 30_000 }, {}, undefined, (update) =>
    updates.push(update),
  );
  assert.notEqual(result.isError, true);
  assert.ok(result.content[0].text.length < 17_000);
  assert.match(result.content[0].text, /Full result:/);
  assert.ok(readFileSync(result.details.resultPath, "utf8").length > 30_000);
  assert.ok(
    updates.some(
      (update) => update.details.workspace === result.details.workspace,
    ),
  );
});

test(
  "Pi dispatches delegate through its validated tool interface",
  { skip: !process.env.PI_SDK_ENTRY },
  async (t) => {
    const h = setup(t);
    const {
      createAgentSession,
      DefaultResourceLoader,
      ModelRuntime,
      SessionManager,
      SettingsManager,
    } = await import(process.env.PI_SDK_ENTRY);
    const runtime = await ModelRuntime.create({
      authPath: join(h.directory, "auth.json"),
      modelsPath: join(h.directory, "models.json"),
    });
    runtime.registerProvider("openai-codex", {
      apiKey: "test",
      api: "openai-responses",
      baseUrl: "http://127.0.0.1:1/v1",
      models: [runtime.getModel("openai-codex", "gpt-6.1-sol")],
    });
    const settingsManager = SettingsManager.inMemory({
      compaction: { enabled: false },
      retry: { enabled: false },
    });
    const loader = new DefaultResourceLoader({
      cwd: h.repo,
      agentDir: h.directory,
      settingsManager,
      noExtensions: true,
      noSkills: true,
      noPromptTemplates: true,
      noThemes: true,
    });
    await loader.reload();
    const { session } = await createAgentSession({
      cwd: h.repo,
      agentDir: h.directory,
      modelRuntime: runtime,
      model: runtime.getModel("openai-codex", "gpt-6.1-sol"),
      resourceLoader: loader,
      settingsManager,
      sessionManager: SessionManager.inMemory(h.repo),
      tools: ["delegate"],
      customTools: [h.tool],
    });
    t.after(() => session.dispose());
    await session.bindExtensions({
      onError: (error) => {
        throw new Error(JSON.stringify(error));
      },
    });
    let requests = 0;
    session.agent.streamFunction = (model) => {
      const first = requests++ === 0;
      const message = {
        role: "assistant",
        api: model.api,
        provider: model.provider,
        model: model.id,
        timestamp: Date.now(),
        stopReason: first ? "toolUse" : "stop",
        usage: {
          input: 0,
          output: 0,
          cacheRead: 0,
          cacheWrite: 0,
          totalTokens: 0,
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
        },
        content: first
          ? [
              {
                type: "toolCall",
                id: "delegate-1",
                name: "delegate",
                arguments: { task: "{}", role: "worker" },
              },
            ]
          : [{ type: "text", text: "done" }],
      };
      return {
        async *[Symbol.asyncIterator]() {
          yield { type: "done", reason: message.stopReason, message };
        },
        async result() {
          return message;
        },
      };
    };
    await session.prompt("Delegate the task.");
    const result = session.messages.find(
      (message) => message.role === "toolResult",
    );
    assert.ok(result, JSON.stringify(session.messages));
    assert.notEqual(result.isError, true, JSON.stringify(result));
    assert.ok(existsSync(result.details.workspace));
    assert.equal(result.usage.totalTokens, 35);
  },
);
