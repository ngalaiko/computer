import test from "node:test";
import assert from "node:assert/strict";
import {
  mkdtempSync,
  rmSync,
  appendFileSync,
  writeFileSync,
  readFileSync,
  statSync,
  chmodSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createJournal } from "./review/shared/journal.mjs";
import { createWatcher } from "./review/pi/watcher.mjs";

function fixture(t, options = {}) {
  const dir = mkdtempSync(join(tmpdir(), "pi-review-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const journal = createJournal({ stateDir: dir, workspace: dir });
  const notices = [];
  let living = true;
  const close = journal.close;
  journal.close = () => {
    living = false;
    close();
  };
  let tick;
  const watcher = createWatcher({
    stateDir: dir,
    isAlive: () => living,
    exec: async () => ({
      code: 0,
      stdout: JSON.stringify({
        session: { sessionId: "native-exact", pid: process.pid, cwd: dir },
      }),
    }),
    notify: async (notice) => notices.push(notice),
    schedule: (callback) => {
      tick = callback;
      return () => {
        tick = null;
      };
    },
    ...options,
  });
  t.after(() => watcher.stop());
  return {
    dir,
    journal,
    watcher,
    notices,
    tick: () => tick?.(),
    start: () =>
      watcher.start({
        workspace: dir,
        session: "native-exact",
        hunkBin: process.execPath,
      }),
  };
}
const human = {
  id: "user:1",
  filePath: "a.ts",
  side: "new",
  line: 3,
  body: "Fix this",
  draft: false,
};

test("real journal delivers initial feedback only in start result and saved feedback after immediate close once", async (t) => {
  const f = fixture(t);
  f.journal.save(human);
  const initial = await f.start();
  assert.equal(initial.feedback[0].body, "Fix this");
  assert.equal(f.notices.length, 0);
  f.journal.save({ ...human, body: "Second saved edit" });
  f.journal.close();
  await f.tick();
  assert.equal(f.notices.length, 1);
  assert.equal(f.notices[0].feedback[0].body, "Second saved edit");
  assert.equal(f.watcher.status().running, false);
});

async function host(t) {
  const f = fixture(t, { isAlive: () => true });
  f.journal.close();
  const { default: factory } = await import("./review/hunk/bridge.ts");
  const events = new Map(),
    commands = new Map(),
    modes = new Map(),
    statuses = new Map(),
    toasts = [],
    panes = new Map();
  let pane;
  const ctx = {
    cwd: f.dir,
    notify: (...args) => toasts.push(args),
    statusLine: {
      set: (item) => statuses.set(item.id, item),
      clear: (id) => statuses.delete(id),
    },
  };
  factory(
    {
      apiVersion: 32,
      events: {
        on: (id, handler) => events.set(id, handler),
        emit: (id, data) => events.get(id)?.(data, ctx),
      },
      registerPane: (spec) => panes.set(spec.id, spec),
      registerKeyboardMode: (mode) => modes.set(mode.id, mode),
      on: (id, handler) => events.set(id, handler),
      registerCommand: (command, handler) =>
        commands.set(command.id, { ...command, handler }),
    },
    {
      stateDir: f.dir,
      renderPane: (store) => {
        pane = store;
        return () => null;
      },
    },
  );
  events.get("startup")({ cwd: f.dir }, ctx);
  t.after(() => events.get("shutdown")({}, ctx));
  return { ...f, events, commands, modes, panes, pane, ctx, statuses, toasts };
}
const agent = {
  id: "agent:1",
  source: "agent",
  parentId: "user:1",
  fileKey: "stable:a",
  summary: "Fixed",
  rationale: "Test added",
  anchor: { preferred: { side: "new", line: 3 }, intersectingHunkIndices: [0] },
  resolution: "active",
};

test("native human callbacks exclude drafts, deduplicate deep semantic saves, and exclude agent store events", async (t) => {
  const f = await host(t);
  f.events.get("note_edited")({ note: { ...human, draft: true } }, f.ctx);
  f.events.get("note_changed")({ kind: "created", note: agent }, f.ctx);
  f.events.get("note_created")({ note: human }, f.ctx);
  f.events.get("note_edited")({ note: { ...human } }, f.ctx);
  f.events.get("note_edited")(
    { note: { ...human, body: "Actually fix it" } },
    f.ctx,
  );
  const initial = await f.start();
  assert.deepEqual(
    initial.feedback.map((n) => n.body),
    ["Fix this", "Actually fix it"],
  );
  assert.equal(
    f.statuses.get("unread").spans[0].text,
    "1 NEW REPLIES — ,n to read",
  );
  f.events.get("note_changed")(
    { kind: "updated", note: { ...agent, updatedAt: "later" } },
    f.ctx,
  );
  assert.equal(f.toasts.length, 1);
  f.events.get("note_changed")(
    { kind: "updated", note: { ...agent, summary: "Different body" } },
    f.ctx,
  );
  assert.equal(f.toasts.length, 2);
  assert.equal(
    f.statuses.get("unread").spans[0].text,
    "1 NEW REPLIES — ,n to read",
  );
});

test("unread navigation uses fresh native mapping; failed landing, hidden/stale/orphaned notes, and unrelated selection retain unread", async (t) => {
  const f = await host(t);
  f.events.get("note_changed")({ kind: "created", note: agent }, f.ctx);
  let notes = [agent],
    files = [{ fileKey: "stable:a", runtimeId: "renumbered:9", path: "a.ts" }];
  const jumps = [];
  const ctx = {
    ...f.ctx,
    review: {
      snapshot: () => ({ generation: "g", stateRevision: 4, notes, files }),
    },
    selection: {
      file: null,
      currentLine: null,
      files: [{ id: "renumbered:9" }],
    },
    navigation: { revealLine: (...args) => jumps.push(args) },
  };
  const next = () => f.commands.get("next").handler(ctx);
  await next();
  assert.deepEqual(jumps, [["renumbered:9", "new", 3]]);
  assert.ok(f.statuses.has("unread"));
  f.events.get("selection_changed")?.({ fileId: "other", hunkIndex: 0 }, f.ctx);
  assert.ok(f.statuses.has("unread"));
  await next(); // A void/no-op reveal is not acknowledged.
  assert.ok(f.statuses.has("unread"));
  ctx.selection.files = [];
  await next();
  assert.equal(jumps.length, 2);
  ctx.selection.files = [{ id: "renumbered:9" }];
  notes = [{ ...agent, resolution: "stale" }];
  await next();
  notes = [{ ...agent, resolution: "orphaned" }];
  await next();
  assert.ok(f.statuses.has("unread"));
  assert.equal(jumps.length, 2);
  notes = [agent];
  await next();
  ctx.selection.file = { id: "renumbered:9" };
  ctx.selection.currentLine = { side: "new", line: 3 };
  await next(); // Fresh command context confirms the requested landing.
  assert.equal(f.statuses.has("unread"), false);
});

test(",n is a public keyboard-mode sequence, Escape cancels without navigation", async (t) => {
  const f = await host(t);
  let snapshots = 0;
  const ctx = {
    ...f.ctx,
    review: {
      snapshot: () => {
        snapshots++;
        return null;
      },
    },
    keyboardModes: { enterMode: () => true },
  };
  assert.equal(f.commands.get("leader").key, ",");
  const command = f.commands.get("leader").handler(ctx);
  assert.equal(
    f.modes.get("leader").onKey({ name: "n", sequence: "n" }),
    "exit",
  );
  f.modes.get("leader").onExit();
  await command;
  assert.equal(snapshots, 1);
  const cancelled = f.commands.get("leader").handler(ctx);
  f.modes.get("leader").onExit();
  await cancelled;
  assert.equal(snapshots, 1);
});

test("reply uses exact native session and human parent with argument-array execution and verified native agent result", async (t) => {
  const f = fixture(t);
  f.journal.save(human);
  await f.start();
  const calls = [];
  let added = false,
    closed = false;
  const reply = '--leading-dash 完整 "reply"; $(no shell)\nFull body';
  // The exec boundary models the installed CLI envelopes and public source metadata.
  f.watcher.stop();
  const watcher = createWatcher({
    stateDir: f.dir,
    notify: async () => {},
    schedule: () => () => {},
    exec: async (bin, args, opts) => {
      calls.push({ bin, args, opts });
      if (closed) return { code: 1, stderr: "No active sessions" };
      let response;
      if (args[1] === "get")
        response = {
          session: { sessionId: "native-exact", pid: process.pid, cwd: f.dir },
        };
      else if (args[2] === "add") {
        added = true;
        response = {
          result: {
            commentId: "live:exact",
            fileId: "f",
            filePath: "a.ts",
            hunkIndex: 0,
            side: "new",
            line: 3,
          },
        };
      } else
        response = {
          comments: [
            { noteId: "user:1", source: "user", body: "Fix this" },
            ...(added
              ? [
                  {
                    noteId: "live:exact",
                    parentId: "user:1",
                    source: "agent",
                    author: "Pi",
                    body: reply,
                  },
                ]
              : []),
          ],
        };
      return { code: 0, stdout: JSON.stringify(response) };
    },
  });
  t.after(() => watcher.stop());
  await watcher.start({
    workspace: f.dir,
    session: "native-exact",
    hunkBin: process.execPath,
  });
  await assert.rejects(
    watcher.reply({ replyTo: "other-human", body: reply }),
    /watched human/,
  );
  const beforeOversize = calls.length;
  await assert.rejects(
    watcher.reply({ replyTo: "user:1", body: "界".repeat(21846) }),
    /64 KiB/,
  );
  assert.equal(calls.length, beforeOversize);
  const result = await watcher.reply({ replyTo: "user:1", body: reply });
  assert.deepEqual(result, {
    commentId: "live:exact",
    parentId: "user:1",
    source: "agent",
    author: "Pi",
  });
  assert.deepEqual(calls.find((call) => call.args[2] === "add").args, [
    "session",
    "comment",
    "add",
    "native-exact",
    "--reply-to",
    "user:1",
    "--summary=" + reply,
    "--author",
    "Pi",
    "--json",
  ]);
  closed = true;
  await assert.rejects(
    watcher.reply({ replyTo: "user:1", body: "Again" }),
    /UI unavailable/,
  );
  assert.equal(calls.filter((call) => call.args[2] === "add").length, 1);
});

test("notification rejection preserves full feedback until accepted, with one poll in flight", async (t) => {
  let accept,
    attempts = 0;
  const notices = [];
  const f = fixture(t, {
    notify: async (notice) => {
      attempts++;
      if (attempts <= 4) throw new Error("temporarily busy");
      await new Promise((resolve) => {
        accept = resolve;
      });
      notices.push(notice);
    },
  });
  await f.start();
  const body = "完整".repeat(90000);
  f.journal.save({ ...human, body });
  for (let i = 0; i < 4; i++) await f.tick();
  assert.equal(f.watcher.status().running, true);
  const pending = f.tick();
  await f.tick();
  assert.equal(attempts, 5);
  accept();
  await pending;
  assert.equal(notices[0].feedback[0].body, body);
  await f.tick();
  assert.equal(attempts, 5);
});

test("save and close during start verification returns complete initial feedback and stops quietly", async (t) => {
  let release;
  const f = fixture(t, {
    exec: () =>
      new Promise((resolve) => {
        release = resolve;
      }),
  });
  const starting = f.start();
  f.journal.save(human);
  f.journal.close();
  release({
    code: 0,
    stdout: JSON.stringify({
      session: { sessionId: "native-exact", pid: process.pid, cwd: f.dir },
    }),
  });
  const result = await starting;
  assert.equal(result.feedback[0].body, "Fix this");
  assert.equal(result.running, false);
  assert.equal(f.notices.length, 0);
});

test("stop, replacement and aborted start ignore late verification and notification completions", async (t) => {
  let release;
  const f = fixture(t, {
    exec: () =>
      new Promise((resolve) => {
        release = resolve;
      }),
  });
  const response = () => ({
    code: 0,
    stdout: JSON.stringify({
      session: { sessionId: "native-exact", pid: process.pid, cwd: f.dir },
    }),
  });
  const first = f.start();
  const firstRelease = release;
  const second = f.start();
  const secondRelease = release;
  firstRelease(response());
  await assert.rejects(first, /replaced or stopped/);
  f.watcher.stop();
  secondRelease(response());
  await assert.rejects(second, /replaced or stopped/);
  const abort = new AbortController();
  const third = f.watcher.start(
    { workspace: f.dir, session: "native-exact", hunkBin: process.execPath },
    abort.signal,
  );
  abort.abort();
  release(response());
  await assert.rejects(third, /abort/i);
  assert.equal(f.watcher.status().running, false);
  assert.equal(f.notices.length, 0);
});

test(
  "Pi host factory is inert, sends full followUp feedback, and stops on session shutdown",
  { skip: !process.env.PI_JITI_MODULE || !process.env.PI_CODING_AGENT_MODULE },
  async (t) => {
    const { pathToFileURL, fileURLToPath } = await import("node:url");
    const { dirname, resolve } = await import("node:path");
    const { createJiti } = await import(
      pathToFileURL(process.env.PI_JITI_MODULE).href
    );
    const jiti = createJiti(import.meta.url, {
      fsCache: false,
      moduleCache: false,
      alias: {
        "@earendil-works/pi-ai": resolve(
          dirname(process.env.PI_CODING_AGENT_MODULE),
          "../node_modules/@earendil-works/pi-ai/dist/index.js",
        ),
      },
    });
    const extension = await jiti.import(
      fileURLToPath(new URL("./review/index.ts", import.meta.url)),
      { default: true },
    );
    const f = fixture(t),
      tools = new Map(),
      events = new Map(),
      messages = [];
    let timer,
      execs = 0;
    t.mock.method(globalThis, "setTimeout", (callback, ms) => {
      assert.equal(ms, 500);
      timer = callback;
      return 1;
    });
    t.mock.method(globalThis, "clearTimeout", () => {
      timer = undefined;
    });
    extension(
      {
        registerTool: (tool) => tools.set(tool.name, tool),
        on: (name, handler) => events.set(name, handler),
        exec: async () => {
          execs++;
          return {
            code: 0,
            stdout: JSON.stringify({
              session: {
                sessionId: "native-exact",
                pid: process.pid,
                cwd: f.dir,
              },
            }),
          };
        },
        sendMessage: (message, options) => messages.push({ message, options }),
      },
      { stateDir: f.dir },
    );
    assert.equal(execs, 0);
    assert.equal(timer, undefined);
    assert.deepEqual([...tools.keys()], ["hunk_watch", "hunk_reply"]);
    assert.match(tools.get("hunk_watch").description, /optional.*issue/i);
    const call = (params) =>
      tools.get("hunk_watch").execute("id", params, undefined, undefined, {});
    await call({
      action: "start",
      workspace: f.dir,
      session: "native-exact",
      hunkBin: process.execPath,
    });
    const { createIssueTracker, writeIssueIndex } =
      await import("./review/shared/issues.mjs");
    const tracker = createIssueTracker();
    tracker.reconcile(snapshot());
    writeIssueIndex(f.dir, f.journal.identity, tracker.state());
    await timer();
    assert.equal(messages.length, 1);
    assert.match(messages[0].message.content, /^Local Hunk issue status:/);
    assert.equal(messages[0].message.details.kind, "issues");
    assert.deepEqual(messages[0].options, {
      triggerTurn: true,
      deliverAs: "followUp",
    });
    messages.length = 0;
    f.journal.save(human);
    f.journal.close();
    await timer();
    assert.equal(messages.length, 1);
    assert.equal(messages[0].message.customType, "hunk-watch");
    assert.match(messages[0].message.content, /^Local Hunk review feedback:/);
    assert.match(messages[0].message.content, /Fix this/);
    assert.deepEqual(messages[0].options, {
      triggerTurn: true,
      deliverAs: "followUp",
    });
    await events.get("session_shutdown")();
    assert.equal(timer, undefined);
    assert.equal((await call({ action: "status" })).details.running, false);
  },
);

test("complete feedback before corrupt sequence is delivered before one permanent error", async (t) => {
  const f = fixture(t);
  await f.start();
  f.journal.save(human);
  appendFileSync(
    f.journal.path,
    JSON.stringify({ kind: "human", seq: 900, ...human }) + "\n",
  );
  await f.tick();
  assert.equal(f.notices[0].kind, "feedback");
  assert.equal(f.notices[0].feedback[0].body, "Fix this");
  for (let i = 0; i < 5; i++) await f.tick();
  assert.equal(f.watcher.status().running, false);
  assert.equal(f.notices.filter((n) => n.kind === "error").length, 1);
});

test(",o shares the public leader mode and dispatches the native files-pane toggle", async (t) => {
  const f = await host(t),
    calls = [];
  const ctx = {
    ...f.ctx,
    keyboardModes: { enterMode: () => true },
    commands: {
      execute: (...args) => {
        calls.push(args);
        return true;
      },
    },
  };
  const pending = f.commands.get("leader").handler(ctx);
  assert.equal(f.modes.get("leader").onKey({ sequence: "o" }), "exit");
  f.modes.get("leader").onExit();
  await pending;
  assert.deepEqual(calls, [["hunk.view.toggleFilesPane"]]);
  assert.equal(
    [...f.commands.values()].some((command) => command.key === ",o"),
    false,
  );
});

test("truncated records retry without acknowledgment and recover; malformed records stop after bounded retries", async (t) => {
  const f = fixture(t);
  await f.start();
  const record =
    JSON.stringify({
      kind: "human",
      seq: 1,
      id: "user:1",
      file: "a.ts",
      line: 3,
      side: "new",
      body: "Whole body",
    }) + "\n";
  appendFileSync(f.journal.path, record.slice(0, -6));
  await f.tick();
  await f.tick();
  assert.equal(f.notices.length, 0);
  appendFileSync(f.journal.path, record.slice(-6));
  await f.tick();
  assert.equal(f.notices[0].feedback[0].body, "Whole body");
  appendFileSync(f.journal.path, "{bad json}\n");
  await f.tick();
  await f.tick();
  await f.tick();
  await f.tick();
  assert.equal(f.notices.length, 2);
  assert.equal(f.notices[1].kind, "error");
});

test("bounded batches drain full feedback in order after close without another native CLI read", async (t) => {
  let execs = 0;
  const f = fixture(t, {
    exec: async () => {
      execs++;
      return {
        code: 0,
        stdout: JSON.stringify({
          session: { sessionId: "native-exact", pid: process.pid, cwd: f.dir },
        }),
      };
    },
  });
  for (let i = 0; i < 8; i++)
    f.journal.save({
      ...human,
      id: `user:${i}`,
      body: `Note ${i}:` + "x".repeat(200000),
    });
  const initial = await f.start();
  assert.equal(initial.more, true);
  f.journal.close();
  for (let i = 0; i < 10 && f.watcher.status().running; i++) await f.tick();
  const delivered = [
    ...initial.feedback,
    ...f.notices.flatMap((n) => n.feedback ?? []),
  ];
  assert.equal(delivered.length, 8);
  assert.deepEqual(
    delivered.map((n) => n.id),
    [
      "user:0",
      "user:1",
      "user:2",
      "user:3",
      "user:4",
      "user:5",
      "user:6",
      "user:7",
    ],
  );
  assert.equal(delivered[7].body.length, 200007);
  assert.equal(execs, 1);
  assert.equal(f.watcher.status().running, false);
});

test("native identity and private state permissions reject cross-review or replaced journals", async (t) => {
  const f = fixture(t);
  assert.equal(statSync(f.dir).mode & 0o777, 0o700);
  assert.equal(statSync(f.journal.path).mode & 0o777, 0o600);
  const descriptor = join(f.dir, `${process.pid}.json`);
  assert.equal(statSync(descriptor).mode & 0o777, 0o600);
  const original = readFileSync(descriptor, "utf8");
  writeFileSync(
    descriptor,
    JSON.stringify({ ...JSON.parse(original), workspace: "/other-review" }),
  );
  await assert.rejects(f.start(), /identity\/workspace/);
  writeFileSync(descriptor, original);
  await f.start();
  writeFileSync(
    descriptor,
    JSON.stringify({ ...JSON.parse(original), nonce: "0".repeat(32) }),
  );
  for (let i = 0; i < 4; i++) await f.tick();
  assert.equal(f.notices.length, 1);
  assert.equal(f.notices[0].kind, "error");
  writeFileSync(descriptor, original);
  chmodSync(descriptor, 0o644);
  await assert.rejects(f.start(), /permissions/);
});

test("native user store edits never alert and snapshots do not count existing agent notes as NEW", async (t) => {
  const f = await host(t);
  f.events.get("note_changed")(
    { kind: "updated", note: { ...agent, id: "user:1", source: "user" } },
    f.ctx,
  );
  assert.equal(f.toasts.length, 0);
  const ctx = {
    ...f.ctx,
    review: {
      snapshot: () => ({
        generation: "g",
        stateRevision: 1,
        files: [],
        notes: [agent],
      }),
    },
    selection: { files: [] },
  };
  await f.commands.get("next").handler(ctx);
  assert.equal(f.statuses.has("unread"), false);
});

test("anchor remapping between jump and confirmation cannot acknowledge an old landing", async (t) => {
  const f = await host(t);
  f.events.get("note_changed")({ kind: "created", note: agent }, f.ctx);
  let note = agent;
  const ctx = {
    ...f.ctx,
    review: {
      snapshot: () => ({
        generation: "g",
        stateRevision: 1,
        files: [{ fileKey: "stable:a", runtimeId: "f" }],
        notes: [note],
      }),
    },
    selection: { files: [{ id: "f" }], file: null, currentLine: null },
    navigation: { revealLine() {} },
  };
  await f.commands.get("next").handler(ctx);
  ctx.selection.file = { id: "f" };
  ctx.selection.currentLine = { side: "new", line: 3 };
  note = {
    ...agent,
    anchor: { ...agent.anchor, preferred: { side: "new", line: 8 } },
  };
  await f.commands.get("next").handler(ctx);
  assert.ok(f.statuses.has("unread"));
});

test("unsupported Hunk API fails visibly before registration; manifest selects only Hunk factory", async () => {
  const { default: factory } = await import("./review/hunk/bridge.ts");
  assert.throws(() => factory({ apiVersion: 31 }), /requires Hunk API 32/);
  assert.throws(() => factory({ apiVersion: 33 }), /requires Hunk API 32/);
  const manifest = JSON.parse(
    readFileSync(new URL("./review/package.json", import.meta.url), "utf8"),
  );
  assert.deepEqual(manifest, {
    private: true,
    type: "module",
    hunk: { apiVersion: 32, extensions: ["./hunk/index.ts"] },
  });
});

test("oversized feedback fails visibly without acknowledging or truncating the next valid semantic save", async (t) => {
  const f = fixture(t);
  assert.throws(
    () => f.journal.save({ ...human, body: "x".repeat(1024 * 1024) }),
    /not transported/,
  );
  f.journal.save({ ...human, body: "Valid complete feedback" });
  const initial = await f.start();
  assert.equal(initial.feedback.length, 1);
  assert.equal(initial.feedback[0].body, "Valid complete feedback");
  assert.equal(initial.feedback[0].seq, 1);
});

test("fresh snapshot prunes dropped unread notes and body deduplication", async (t) => {
  const f = await host(t);
  f.events.get("note_changed")({ kind: "created", note: agent }, f.ctx);
  let notes = [agent];
  const ctx = {
    ...f.ctx,
    review: {
      snapshot: () => ({
        generation: "g",
        notes,
        files: [{ fileKey: agent.fileKey, runtimeId: "a" }],
      }),
    },
    selection: { files: [{ id: "a" }] },
    navigation: { revealLine: () => {} },
  };
  await f.commands.get("next").handler(ctx);
  assert.ok(f.statuses.has("unread"));
  notes = [];
  await f.commands.get("next").handler(ctx);
  assert.equal(f.statuses.has("unread"), false);
  f.events.get("note_changed")({ kind: "created", note: agent }, f.ctx);
  assert.ok(f.statuses.has("unread"));
});

for (const closeOld of [false, true]) {
  test(`registry replacement drains old saved feedback before one error (closed=${closeOld})`, async (t) => {
    let reject = true;
    const notices = [];
    const f = fixture(t, {
      isAlive: () => true,
      notify: async (notice) => {
        if (notice.kind === "feedback" && reject) throw new Error("busy");
        notices.push(notice);
      },
    });
    await f.start();
    f.journal.save(human);
    if (closeOld) f.journal.close();
    const replacement = createJournal({ stateDir: f.dir, workspace: f.dir });
    t.after(() => replacement.close());
    await f.tick();
    assert.deepEqual(notices, []);
    reject = false;
    for (let i = 0; i < 5; i++) await f.tick();
    assert.deepEqual(
      notices.map((n) => n.kind),
      ["feedback", "error"],
    );
    assert.equal(notices[0].feedback[0].body, human.body);
    assert.match(notices[1].error, /reverify|restart/i);
    assert.equal(f.watcher.status().running, false);
  });
}

test("closed bridge with living UI errors once; normal shutdown grace stops quietly", async (t) => {
  for (const shutdown of [false, true]) {
    let living = true;
    const f = fixture(t, { isAlive: () => living });
    await f.start();
    f.journal.close();
    await f.tick();
    assert.equal(f.watcher.status().running, true);
    if (shutdown) living = false;
    for (let i = 0; i < 4; i++) await f.tick();
    assert.equal(f.watcher.status().running, false);
    assert.equal(f.notices.length, shutdown ? 0 : 1);
    if (!shutdown) assert.match(f.notices[0].error, /reverify|restart/i);
  }
});

const root = {
  ...agent,
  id: "user:1",
  source: "user",
  parentId: undefined,
  summary: "Fix this",
};
const snapshot = (notes = [root], generation = "g1", stateRevision = 1) => ({
  generation,
  stateRevision,
  notes,
  files: [{ fileKey: "stable:a", runtimeId: "current:7", path: "a.ts" }],
});

test("issues group human descendants by stable human root; only human body changes reopen", async () => {
  const { createIssueTracker } = await import("./review/shared/issues.mjs");
  const tracker = createIssueTracker();
  const reply = { ...root, id: "user:2", parentId: agent.id, summary: "More" };
  tracker.reconcile(snapshot([root, agent, reply]));
  assert.equal(tracker.state().open, 1);
  assert.equal(tracker.toggle(root.id), true);
  assert.equal(tracker.state().open, 0);
  tracker.reconcile(
    snapshot([root, { ...agent, summary: "Done" }, reply], "g2"),
  );
  assert.equal(tracker.state().open, 0);
  assert.equal(tracker.locationVerified(root.id), false);
  tracker.reconcile(
    snapshot(
      [
        { ...root, anchor: { preferred: { side: "new", line: 20 } } },
        agent,
        reply,
      ],
      "g2",
    ),
  );
  assert.equal(tracker.state().open, 0);
  tracker.reconcile(
    snapshot([root, agent, { ...reply, summary: "Changed" }], "g2"),
  );
  assert.equal(tracker.state().open, 1);
  tracker.toggle(root.id);
  tracker.reconcile(
    snapshot([{ ...root, summary: "Changed root" }, agent, reply], "g2"),
  );
  assert.equal(tracker.state().open, 1);
  tracker.reconcile(snapshot([]));
  assert.equal(tracker.state().items.length, 0);
  tracker.reconcile(snapshot([reply, { ...agent, parentId: reply.id }]));
  assert.equal(tracker.state().items.length, 0);
  tracker.reconcile(snapshot([{ ...root, parentId: "missing" }]));
  assert.equal(tracker.state().items.length, 0);
});

test("private atomic issue sidecar validates complete schema, bounds, identity, ownership modes and symlinks", async (t) => {
  const {
    createIssueTracker,
    writeIssueIndex,
    readIssueIndex,
    issuePath,
    MAX_ISSUE_BYTES,
    MAX_ISSUES,
  } = await import("./review/shared/issues.mjs");
  const { symlinkSync, unlinkSync } = await import("node:fs");
  const f = fixture(t),
    tracker = createIssueTracker();
  assert.deepEqual(readIssueIndex(f.dir, f.journal.identity), {
    available: false,
  });
  tracker.reconcile(snapshot());
  writeIssueIndex(f.dir, f.journal.identity, tracker.state());
  const path = issuePath(f.dir, f.journal.identity);
  assert.equal(statSync(path).mode & 0o777, 0o600);
  assert.equal(readIssueIndex(f.dir, f.journal.identity).items[0].id, root.id);
  const original = readFileSync(path, "utf8");
  for (const mutate of [
    (v) => {
      v.identity.workspace = "/elsewhere";
    },
    (v) => {
      v.identity.pid++;
    },
    (v) => {
      v.identity.nonce = "0".repeat(32);
    },
    (v) => {
      v.issues.revision = -1;
    },
    (v) => {
      delete v.coveredHumanSequence;
    },
    (v) => {
      v.coveredHumanSequence = -1;
    },
    (v) => {
      v.coveredHumanSequence = 0.5;
    },
    (v) => {
      v.issues.items[0].status = "active";
    },
    (v) => {
      v.issues.items[0].extra = true;
    },
    (v) => {
      v.issues.items.push(v.issues.items[0]);
    },
    (v) => {
      v.issues.items = Array(MAX_ISSUES + 1).fill(v.issues.items[0]);
    },
    (v) => {
      v.issues.open = 0;
    },
  ]) {
    const value = JSON.parse(original);
    mutate(value);
    writeFileSync(path, JSON.stringify(value));
    assert.throws(
      () => readIssueIndex(f.dir, f.journal.identity),
      /issue|identity/i,
    );
  }
  writeFileSync(path, "x".repeat(MAX_ISSUE_BYTES + 1));
  assert.throws(() => readIssueIndex(f.dir, f.journal.identity), /limit/);
  writeFileSync(path, original);
  chmodSync(path, 0o644);
  assert.throws(() => readIssueIndex(f.dir, f.journal.identity), /permissions/);
  chmodSync(path, 0o600);
  unlinkSync(path);
  symlinkSync(f.journal.path, path);
  assert.throws(() => readIssueIndex(f.dir, f.journal.identity));
  unlinkSync(path);
  writeFileSync(path, original, { mode: 0o600 });
  chmodSync(f.dir, 0o755);
  assert.throws(() => readIssueIndex(f.dir, f.journal.identity), /permissions/);
  chmodSync(f.dir, 0o700);
});

async function issueHost(t, notes = [root]) {
  const f = await host(t);
  let current = snapshot(notes),
    choose = () => null;
  const jumps = [];
  const ctx = {
    ...f.ctx,
    review: { snapshot: () => current },
    selection: { files: [{ id: "current:7" }], file: null, currentLine: null },
    navigation: { revealLine: (...args) => jumps.push(args) },
    dialogs: { select: (options) => choose(options) },
    keyboardModes: { enterMode: () => true },
  };
  const pick = () => f.commands.get("issues").handler(ctx);
  return {
    ...f,
    ctx,
    jumps,
    pick,
    set: (value) => {
      current = value;
    },
    choose: (fn) => {
      choose = fn;
    },
  };
}
async function issueState(f) {
  const { readIssueIndex } = await import("./review/shared/issues.mjs");
  const identity = JSON.parse(
    readFileSync(join(f.dir, `${process.pid}.json`), "utf8"),
  );
  return readIssueIndex(f.dir, identity);
}

test("factory chooser resolves/reopens exactly ordinal root, cancel safe, duplicate labels distinct; counts coexist with NEW", async (t) => {
  const second = { ...root, id: "user:other" };
  const f = await issueHost(t, [root, second, agent]);
  await f.pick();
  assert.equal((await issueState(f)).open, 2);
  f.choose(({ options, title }) => {
    assert.match(title, /extension issue status/i);
    assert.match(options[0], /^1\. \[open\] a.ts/);
    assert.match(options[1], /^2\. \[open\] a.ts/);
    return options[1];
  });
  await f.pick();
  assert.deepEqual(
    (await issueState(f)).items.map((i) => i.status),
    ["open", "resolved"],
  );
  f.choose(({ options }) => {
    assert.match(options[1], /\[resolved\]/);
    return options[1];
  });
  await f.pick();
  assert.equal((await issueState(f)).open, 2);
  assert.deepEqual(f.jumps, []);
  f.events.get("note_changed")({ kind: "created", note: agent }, f.ctx);
  const item = f.statuses.get("unread");
  assert.match(
    item.spans.map((s) => s.text).join(""),
    /1 NEW REPLIES.*2 open.*extension issue status/i,
  );
  assert.equal(f.statuses.has("issues"), false);
  f.choose(() => null);
  const before = await issueState(f);
  await f.pick();
  assert.deepEqual(await issueState(f), before);
  assert.deepEqual(f.jumps, []);
});

test("factory rejects awaited chooser after deletion, body/revision/generation change or concurrent status toggle", async (t) => {
  for (const change of ["delete", "body", "revision", "generation", "status"]) {
    const f = await issueHost(t);
    let release;
    f.choose(
      ({ options }) =>
        new Promise((resolve) => {
          release = () => resolve(options[0]);
        }),
    );
    const pending = f.pick();
    if (change === "status") {
      f.choose(({ options }) => options[0]);
      await f.pick();
    } else
      f.set(
        snapshot(
          change === "delete"
            ? []
            : [
                {
                  ...root,
                  ...(change === "body" ? { summary: "Edited" } : {}),
                },
              ],
          change === "generation" ? "g2" : "g1",
          change === "revision" ? 2 : 1,
        ),
      );
    release();
    await pending;
    assert.match(f.toasts.at(-1)[0], /changed|deleted/i);
    assert.equal(
      (await issueState(f)).open,
      change === "delete" || change === "status" ? 0 : 1,
    );
  }
});

test("factory reload preserves issue status, invalidates active old anchors, prunes deletion, reopens only human body edits", async (t) => {
  const f = await issueHost(t);
  await f.pick();
  await f.commands.get("next-issue").handler(f.ctx);
  assert.deepEqual(f.jumps, [["current:7", "new", 3]]);
  f.choose(({ options }) => options[0]);
  await f.pick();
  f.events.get("note_changed")({ kind: "created", note: agent }, f.ctx);
  assert.equal((await issueState(f)).open, 0);
  f.events.get("session_reload")({ reason: "daemon" }, f.ctx);
  assert.equal((await issueState(f)).available, false);
  f.set(snapshot([root, agent], "g2"));
  f.choose(() => null);
  await f.pick();
  assert.equal((await issueState(f)).open, 0);
  f.choose(({ options }) => options[0]);
  await f.pick();
  await f.commands.get("next-issue").handler(f.ctx);
  assert.equal(f.jumps.length, 1);
  assert.match(f.toasts.at(-1)[0], /reload|unverified/i);
  f.choose(({ options }) => options[0]);
  await f.pick();
  const edited = { ...root, summary: "Human edit" };
  f.events.get("note_changed")({ kind: "updated", note: edited }, f.ctx);
  assert.equal((await issueState(f)).open, 1);
  f.events.get("note_changed")({ kind: "removed", note: edited }, f.ctx);
  assert.equal((await issueState(f)).items.length, 0);
});

test(",r and ,u use the existing public leader; hidden/stale/missing issue anchors never navigate", async (t) => {
  const f = await issueHost(t);
  for (const key of ["r", "u"]) {
    const pending = f.commands.get("leader").handler(f.ctx);
    f.modes.get("leader").onKey({ sequence: key });
    f.modes.get("leader").onExit();
    await pending;
  }
  assert.equal(f.jumps.length, 1);
  for (const note of [
    { ...root, resolution: "stale" },
    { ...root, resolution: "orphaned" },
    { ...root, anchor: {} },
  ]) {
    f.set(snapshot([note]));
    await f.commands.get("next-issue").handler(f.ctx);
  }
  f.set(snapshot());
  f.ctx.selection.files = [];
  await f.commands.get("next-issue").handler(f.ctx);
  assert.equal(f.jumps.length, 1);
});

test("watcher returns initial issues once, combines human feedback, retries status-only delivery without granting reply authority", async (t) => {
  const { createIssueTracker, writeIssueIndex } =
    await import("./review/shared/issues.mjs");
  let reject = false;
  const notices = [];
  const f = fixture(t, {
    notify: async (notice) => {
      if (reject) throw new Error("busy");
      notices.push(notice);
    },
  });
  const tracker = createIssueTracker();
  tracker.reconcile(snapshot());
  const publish = () =>
    writeIssueIndex(
      f.dir,
      f.journal.identity,
      tracker.state(),
      f.journal.humanSequence,
    );
  publish();
  const initial = await f.start();
  assert.equal(initial.issues.available, true);
  assert.equal(initial.issues.items[0].status, "open");
  await f.tick();
  assert.equal(notices.length, 0);
  tracker.toggle(root.id);
  publish();
  reject = true;
  await f.tick();
  await f.tick();
  assert.equal(notices.length, 0);
  reject = false;
  await f.tick();
  await f.tick();
  assert.equal(notices.length, 1);
  assert.equal(notices[0].kind, "issues");
  assert.equal(notices[0].feedback, undefined);
  assert.equal(notices[0].issues.items[0].status, "resolved");
  await assert.rejects(
    f.watcher.reply({ replyTo: root.id, body: "Not authorized" }),
    /watched human/,
  );
  tracker.toggle(root.id);
  f.journal.save(human);
  publish();
  await f.tick();
  await f.tick();
  assert.equal(notices.length, 2);
  assert.equal(notices[1].kind, "feedback");
  assert.equal(notices[1].issues.items[0].status, "open");
  assert.equal(notices[1].feedback[0].body, human.body);
  assert.equal(f.watcher.status().issues.revision, tracker.state().revision);
});

test("watcher old UI is explicitly unavailable; malformed or regressed issue index fails visibly without losing real feedback", async (t) => {
  const { createIssueTracker, writeIssueIndex, issuePath } =
    await import("./review/shared/issues.mjs");
  const f = fixture(t);
  assert.deepEqual((await f.start()).issues, { available: false });
  assert.deepEqual(f.watcher.status().issues, { available: false });
  const tracker = createIssueTracker();
  tracker.reconcile(snapshot());
  writeIssueIndex(f.dir, f.journal.identity, tracker.state());
  await f.tick();
  assert.equal(f.notices[0].kind, "issues");
  tracker.toggle(root.id);
  writeIssueIndex(f.dir, f.journal.identity, tracker.state());
  await f.tick();
  const path = issuePath(f.dir, f.journal.identity),
    valid = readFileSync(path, "utf8");
  f.journal.save(human);
  writeFileSync(path, "{broken");
  await f.tick();
  assert.equal(f.notices.at(-1).kind, "feedback");
  assert.equal(f.notices.at(-1).issues.available, false);
  for (let i = 0; i < 4; i++) await f.tick();
  assert.equal(f.notices.filter((n) => n.kind === "error").length, 0);
  assert.equal(f.watcher.status().running, true);
  writeFileSync(path, valid);
  await f.start();
  const previous = JSON.parse(valid);
  previous.issues.revision--;
  writeFileSync(path, JSON.stringify(previous));
  for (let i = 0; i < 4; i++) await f.tick();
  assert.match(f.notices.at(-1).issues.error, /revision/i);
});

test("bounded issue state fails explicitly, recovers from a valid snapshot, and verifies only newly observed post-reload locations", async () => {
  const { createIssueTracker, MAX_ISSUES } =
    await import("./review/shared/issues.mjs");
  const tracker = createIssueTracker();
  tracker.reconcile(
    snapshot(
      Array.from({ length: MAX_ISSUES + 1 }, (_, i) => ({
        ...root,
        id: `user:${i}`,
      })),
    ),
  );
  assert.equal(tracker.state().available, false);
  assert.match(tracker.state().error, /limit/);
  tracker.reconcile(snapshot());
  tracker.invalidate();
  const fresh = { ...root, id: "user:fresh" };
  tracker.observe(fresh);
  tracker.reconcile(snapshot([root, fresh], "g2"));
  assert.equal(tracker.locationVerified(root.id), false);
  assert.equal(tracker.locationVerified(fresh.id), false);
});

test("new human replies reopen only their human root, agent/AI edits never do, and snapshot records stay intact", async (t) => {
  const f = await issueHost(t, [root, { ...root, id: "user:other" }]);
  f.choose(({ options }) => options[0]);
  await f.pick();
  const ai = { ...agent, id: "ai:1", source: "ai" };
  const before = JSON.stringify([root, agent, ai]);
  for (const note of [agent, ai]) {
    f.events.get("note_changed")({ kind: "created", note }, f.ctx);
    f.events.get("note_changed")(
      { kind: "updated", note: { ...note, summary: "Done" } },
      f.ctx,
    );
  }
  assert.equal((await issueState(f)).items[0].status, "resolved");
  const humanReply = {
    ...root,
    id: "user:reply",
    parentId: ai.id,
    summary: "Still broken",
  };
  f.events.get("note_changed")({ kind: "created", note: humanReply }, f.ctx);
  assert.equal((await issueState(f)).items[0].status, "open");
  assert.equal((await issueState(f)).items.length, 2);
  assert.equal(JSON.stringify([root, agent, ai]), before);
  assert.deepEqual(f.jumps, []);
});

test("malformed issue sidecar preserves start feedback and equal-revision faults never stop the watch", async (t) => {
  const { createIssueTracker, writeIssueIndex, issuePath } =
    await import("./review/shared/issues.mjs");
  const f = fixture(t),
    tracker = createIssueTracker();
  tracker.reconcile(snapshot());
  writeIssueIndex(f.dir, f.journal.identity, tracker.state());
  const path = issuePath(f.dir, f.journal.identity),
    good = readFileSync(path, "utf8");
  writeFileSync(path, "{bad");
  f.journal.save(human);
  const initial = await f.start();
  assert.equal(initial.issues.available, false);
  assert.match(initial.issues.error, /Malformed issue/);
  assert.equal(initial.feedback[0].body, human.body);
  assert.equal(initial.running, true);
  for (let i = 0; i < 5; i++) await f.tick();
  assert.equal(f.watcher.status().running, true);
  assert.equal(f.notices.length, 1);
  assert.equal(f.notices[0].kind, "issues");
  assert.match(f.notices[0].issues.error, /Malformed issue/);
  writeFileSync(path, good);
  await f.tick();
  f.notices.length = 0;
  const changed = JSON.parse(good);
  changed.issues.items[0].locationVerified = false;
  writeFileSync(path, JSON.stringify(changed));
  for (let i = 0; i < 4; i++) await f.tick();
  assert.equal(f.watcher.status().running, true);
  assert.equal(f.notices.length, 1);
  assert.equal(f.notices[0].kind, "issues");
  assert.match(f.notices[0].issues.error, /revision/);
  f.journal.save({ ...human, body: "Transport still works" });
  await f.tick();
  assert.equal(f.notices.at(-1).feedback[0].body, "Transport still works");
  await f.tick();
  assert.equal(f.notices.length, 2);
});

test("issue-index write failures stay visible without suppressing NEW replies or human journal saves", async (t) => {
  const f = await issueHost(t);
  await f.pick();
  chmodSync(f.dir, 0o755);
  const note = { ...root, id: "user:second" };
  f.events.get("note_changed")({ kind: "created", note }, f.ctx);
  f.events.get("note_changed")({ kind: "created", note: agent }, f.ctx);
  f.events.get("note_created")({ note: human }, f.ctx);
  assert.match(f.statuses.get("unread").spans[0].text, /1 NEW/);
  assert.ok(f.toasts.some(([text]) => /issue index unavailable/i.test(text)));
  chmodSync(f.dir, 0o700);
  assert.equal((await f.start()).feedback[0].body, human.body);
});

test("publication failures deduplicate by code until recovery without suppressing NEW replies", async (t) => {
  const f = await issueHost(t);
  await f.pick();
  const note = { ...root, id: "user:second" };
  const changed = () =>
    f.events.get("note_changed")({ kind: "updated", note }, f.ctx);
  const failures = () =>
    f.toasts.filter(([text]) => /issue index unavailable/i.test(text));
  try {
    chmodSync(f.dir, 0o500);
    for (let i = 0; i < 4; i++) changed();
    f.events.get("note_changed")({ kind: "created", note: agent }, f.ctx);
    assert.equal(failures().length, 1);
    assert.match(failures()[0][0], /^Issue index unavailable: EACCES$/);
    assert.equal(f.toasts.filter(([text]) => /NEW agent/.test(text)).length, 1);
    chmodSync(f.dir, 0o700);
    changed();
    const failed = await issueState(f);
    chmodSync(f.dir, 0o500);
    for (let i = 0; i < 4; i++) changed();
    chmodSync(f.dir, 0o700);
    changed();
    assert.deepEqual(await issueState(f), failed);
    assert.equal(failures().length, 1);
    await f.pick();
    assert.equal((await issueState(f)).available, true);
    chmodSync(f.dir, 0o500);
    f.events.get("note_changed")({ kind: "removed", note }, f.ctx);
    for (let i = 0; i < 4; i++) changed();
    assert.equal(failures().length, 2);
  } finally {
    chmodSync(f.dir, 0o700);
  }
});

test("factory saved human reply fences readable resolved sidecar when private directory denies publication", async (t) => {
  const f = await issueHost(t);
  f.events.get("note_created")({ note: human }, f.ctx);
  f.events.get("note_changed")({ kind: "created", note: root }, f.ctx);
  f.choose(({ options }) => options[0]);
  await f.pick();
  assert.equal((await f.start()).issues.open, 0);
  chmodSync(f.dir, 0o500);
  try {
    const reply = {
      ...human,
      id: "user:reply",
      parentId: root.id,
      body: "Still broken",
    };
    f.events.get("note_created")({ note: reply }, f.ctx);
    // A status peek observes the save without accepting or delivering it.
    assert.equal(f.watcher.status().issues.available, false);
    f.events.get("note_changed")(
      {
        kind: "created",
        note: {
          ...root,
          id: reply.id,
          parentId: root.id,
          summary: reply.body,
        },
      },
      f.ctx,
    );
    assert.equal((await issueState(f)).open, 0); // Old private sidecar remains readable.
    assert.ok(f.toasts.some(([text]) => /issue index unavailable/i.test(text)));
    await f.tick();
    assert.equal(f.notices.at(-1).kind, "feedback");
    assert.equal(f.notices.at(-1).feedback[0].body, reply.body);
    assert.equal(f.notices.at(-1).issues.available, false);
    for (let i = 0; i < 4; i++) await f.tick();
    assert.equal(f.watcher.status().running, true);
    assert.equal(f.watcher.status().issues.available, false);
    assert.equal(f.notices.filter((n) => n.feedback).length, 1);
  } finally {
    chmodSync(f.dir, 0o700);
  }
});

test("failed toggle publication never reports success", async (t) => {
  const f = await issueHost(t);
  await f.pick();
  f.choose(({ options }) => {
    chmodSync(f.dir, 0o500);
    return options[0];
  });
  try {
    await f.pick();
    assert.ok(f.toasts.some(([text]) => /issue index unavailable/i.test(text)));
    assert.equal(
      f.toasts.some(([text]) => /^(?:undefined|\d+) open/.test(text)),
      false,
    );
    assert.match(f.statuses.get("issues").spans[0].text, /unavailable/);
  } finally {
    chmodSync(f.dir, 0o700);
  }
});

test("factory verifies initial navigation but not notes observed in an unknown post-reload generation", async (t) => {
  const f = await issueHost(t);
  f.events.get("note_changed")({ kind: "created", note: root }, f.ctx);
  await f.commands.get("next-issue").handler(f.ctx);
  assert.equal(f.jumps.length, 1);
  f.events.get("session_reload")({}, f.ctx);
  const uncertain = { ...root, id: "user:uncertain" };
  f.events.get("note_changed")({ kind: "created", note: uncertain }, f.ctx);
  f.set(snapshot([uncertain], "g2"));
  await f.commands.get("next-issue").handler(f.ctx);
  assert.equal(f.jumps.length, 1);
  assert.match(f.toasts.at(-1)[0], /unverified/);
  const fresh = { ...root, id: "user:fresh" };
  f.events.get("note_changed")({ kind: "created", note: fresh }, f.ctx);
  f.set(snapshot([fresh], "g2"));
  await f.commands.get("next-issue").handler(f.ctx);
  assert.equal(f.jumps.length, 2);
});

test("factory reconciliation alone invalidates anchors across generations and preserves resolved state", async (t) => {
  const f = await issueHost(t);
  await f.commands.get("next-issue").handler(f.ctx);
  assert.equal(f.jumps.length, 1);
  f.set(snapshot([root], "g2"));
  await f.commands.get("next-issue").handler(f.ctx);
  assert.equal(f.jumps.length, 1);
  f.choose(({ options }) => options[0]);
  await f.pick();
  f.set(snapshot([root], "g3"));
  f.choose(() => null);
  await f.pick();
  assert.equal((await issueState(f)).open, 0);
  const fresh = { ...root, id: "user:new" };
  f.events.get("note_changed")({ kind: "created", note: fresh }, f.ctx);
  f.set(snapshot([root, fresh], "g3"));
  await f.commands.get("next-issue").handler(f.ctx);
  assert.equal(f.jumps.length, 2);
});

test(",n requires two presses and issue reconciliation never clears unread", async (t) => {
  const f = await issueHost(t, [root, agent]);
  f.events.get("note_changed")({ kind: "created", note: agent }, f.ctx);
  const next = () => f.commands.get("next").handler(f.ctx);
  await next();
  assert.ok(f.statuses.has("unread"));
  await f.pick();
  await f.commands.get("next-issue").handler(f.ctx);
  assert.ok(f.statuses.has("unread"));
  await next(); // No confirmed landing.
  assert.ok(f.statuses.has("unread"));
  f.ctx.selection.file = { id: "current:7" };
  f.ctx.selection.currentLine = { side: "new", line: 3 };
  await f.pick();
  assert.ok(f.statuses.has("unread"));
  await next();
  assert.equal(f.statuses.has("unread"), false);
});

test("factory coverage advances only after matching human changes, including unchanged issue revisions", async (t) => {
  const { issuePath } = await import("./review/shared/issues.mjs");
  const f = await issueHost(t);
  await f.pick();
  const identity = JSON.parse(
    readFileSync(join(f.dir, `${process.pid}.json`), "utf8"),
  );
  const raw = () =>
    JSON.parse(readFileSync(issuePath(f.dir, identity), "utf8"));
  const revision = raw().issues.revision;
  await f.start();
  const edited = { ...human, body: "Human body edit" };
  f.events.get("note_edited")({ note: edited }, f.ctx);
  f.events.get("note_changed")({ kind: "created", note: agent }, f.ctx);
  assert.equal(raw().coveredHumanSequence, 0);
  assert.equal(f.watcher.status().issues.available, false);
  f.events.get("note_changed")(
    { kind: "updated", note: { ...root, summary: edited.body } },
    f.ctx,
  );
  assert.equal(raw().coveredHumanSequence, 1);
  assert.equal(raw().issues.revision, revision);
  assert.equal(f.watcher.status().issues.open, 1);
  await f.tick();
  await f.tick();
  assert.equal(f.notices.length, 1);
  assert.equal(f.notices[0].feedback[0].body, edited.body);
  // Deduplicated saves consume no human sequence.
  f.events.get("note_edited")({ note: edited }, f.ctx);
  assert.equal(raw().coveredHumanSequence, 1);
  const second = { ...human, id: "user:second" };
  f.events.get("note_created")({ note: second }, f.ctx);
  f.events.get("note_edited")(
    { note: { ...edited, body: "Third save" } },
    f.ctx,
  );
  f.events.get("note_changed")(
    { kind: "updated", note: { ...root, summary: "Third save" } },
    f.ctx,
  );
  assert.equal(raw().coveredHumanSequence, 1);
  f.events.get("note_changed")(
    { kind: "created", note: { ...root, id: second.id } },
    f.ctx,
  );
  assert.equal(raw().coveredHumanSequence, 3);
});

for (const command of ["issues", "next-issue", "next"]) {
  for (const scenario of ["changed-before-save", "anchor-only", "superseded"]) {
    test(`${command} snapshot recovers saved-note coverage: ${scenario}`, async (t) => {
      const { issuePath } = await import("./review/shared/issues.mjs");
      const f = await issueHost(t);
      await f.pick();
      await f.start();
      const identity = JSON.parse(
        readFileSync(join(f.dir, `${process.pid}.json`), "utf8"),
      );
      const raw = () =>
        JSON.parse(readFileSync(issuePath(f.dir, identity), "utf8"));
      let notes = [root, agent],
        count = 1;
      if (scenario === "changed-before-save") {
        f.events.get("note_changed")({ kind: "created", note: root }, f.ctx);
        f.events.get("note_created")({ note: human }, f.ctx);
      } else if (scenario === "anchor-only") {
        f.events.get("note_edited")({ note: { ...human, line: 8 } }, f.ctx);
        notes = [
          { ...root, anchor: { preferred: { side: "new", line: 8 } } },
          agent,
        ];
      } else {
        f.events.get("note_created")({ note: human }, f.ctx);
        f.events.get("note_edited")(
          { note: { ...human, body: "Superseded" } },
          f.ctx,
        );
        f.events.get("note_edited")(
          { note: { ...human, body: "Final body" } },
          f.ctx,
        );
        f.events.get("note_created")(
          { note: { ...human, id: "user:second" } },
          f.ctx,
        );
        notes = [
          { ...root, summary: "Final body" },
          { ...root, id: "user:second" },
          agent,
        ];
        count = 4;
      }
      f.events.get("note_changed")({ kind: "created", note: agent }, f.ctx);
      assert.equal(raw().coveredHumanSequence, 0);
      assert.equal(f.watcher.status().issues.available, false);
      f.set(snapshot(notes, "g1", 2));
      await f.commands.get(command).handler(f.ctx);
      assert.equal(raw().coveredHumanSequence, count);
      assert.equal(f.watcher.status().issues.available, true);
      assert.equal(
        (await issueState(f)).open,
        scenario === "superseded" ? 2 : 1,
      );
      assert.ok(f.statuses.has("unread"));
      await f.tick();
      assert.equal(f.notices.filter((notice) => notice.feedback).length, 1);
      assert.equal(
        f.notices.find((notice) => notice.feedback).feedback.length,
        count,
      );
      await f.tick();
      assert.equal(f.notices.filter((notice) => notice.feedback).length, 1);
    });
  }

  test(`${command} null snapshot retains pending coverage and unknown status`, async (t) => {
    const { issuePath } = await import("./review/shared/issues.mjs");
    const f = await issueHost(t, []);
    await f.pick();
    await f.start();
    f.events.get("note_created")({ note: human }, f.ctx);
    f.set(null);
    await f.commands.get(command).handler(f.ctx);
    const identity = JSON.parse(
      readFileSync(join(f.dir, `${process.pid}.json`), "utf8"),
    );
    const raw = JSON.parse(readFileSync(issuePath(f.dir, identity), "utf8"));
    assert.equal(raw.coveredHumanSequence, 0);
    assert.equal(raw.issues.available, false);
    assert.equal(f.watcher.status().issues.available, false);
    f.set(snapshot([root], "g1", 2));
    await f.commands.get(command).handler(f.ctx);
    assert.equal(f.watcher.status().issues.open, 1);
  });
}

test("chooser rejects a stale selection while its fresh snapshot recovers pending saves", async (t) => {
  const f = await issueHost(t);
  let release;
  f.choose(
    ({ options }) =>
      new Promise((resolve) => {
        release = () => resolve(options[0]);
      }),
  );
  const pending = f.pick();
  f.events.get("note_edited")(
    { note: { ...human, body: "Edited while choosing" } },
    f.ctx,
  );
  f.set(snapshot([{ ...root, summary: "Edited while choosing" }], "g1", 2));
  release();
  await pending;
  assert.match(f.toasts.at(-1)[0], /changed.*choose again/);
  assert.equal((await issueState(f)).open, 1);
  assert.equal((await f.start()).issues.available, true);
});

test("raw issue state and coverage remain monotonic independently of derived stale status", async (t) => {
  const { createIssueTracker, writeIssueIndex, issuePath } =
    await import("./review/shared/issues.mjs");
  const f = fixture(t),
    tracker = createIssueTracker();
  tracker.reconcile(snapshot());
  tracker.toggle(root.id);
  const state = tracker.state();
  const publish = (issues, coverage) =>
    writeIssueIndex(f.dir, f.journal.identity, issues, coverage);
  publish(state, 0);
  assert.equal((await f.start()).issues.open, 0);
  f.journal.save(human);
  assert.equal(f.watcher.status().issues.available, false);
  // Fresh coverage cannot bless changed state at the same issue revision.
  publish(
    { ...state, open: 1, items: [{ ...state.items[0], status: "open" }] },
    1,
  );
  assert.match(f.watcher.status().issues.error, /revision/);
  publish(state, 1);
  assert.equal(f.watcher.status().issues.open, 0);
  publish({ ...state, revision: state.revision + 1 }, 0);
  assert.match(f.watcher.status().issues.error, /sequence.*regressed/);
  publish({ ...state, revision: state.revision - 1 }, 2);
  assert.match(f.watcher.status().issues.error, /revision/);
  publish(state, 1);
  assert.equal(f.watcher.status().issues.open, 0);
  // Peeks and rejected snapshots never consume real feedback.
  await f.tick();
  await f.tick();
  assert.equal(f.notices.length, 1);
  assert.equal(f.notices[0].feedback[0].seq, 1);
  const path = issuePath(f.dir, f.journal.identity);
  const { unlinkSync } = await import("node:fs");
  unlinkSync(path);
  assert.equal(f.watcher.status().issues.available, false);
  assert.match(f.watcher.status().issues.error, /revision/);
  for (let i = 0; i < 5; i++) await f.tick();
  assert.equal(f.watcher.status().running, true);
  assert.equal(f.notices.length, 2);
  assert.equal(f.notices[1].kind, "issues");
});

test("optional index faults at start and during polling preserve transport and deduplicate status errors", async (t) => {
  const { createIssueTracker, writeIssueIndex, issuePath, MAX_ISSUE_BYTES } =
    await import("./review/shared/issues.mjs");
  for (const fault of ["oversized", "permission", "identity"]) {
    await t.test(fault, async (t) => {
      const f = fixture(t),
        tracker = createIssueTracker();
      tracker.reconcile(snapshot());
      writeIssueIndex(f.dir, f.journal.identity, tracker.state());
      const path = issuePath(f.dir, f.journal.identity);
      if (fault === "oversized")
        writeFileSync(path, "x".repeat(MAX_ISSUE_BYTES + 1));
      if (fault === "permission") chmodSync(path, 0o644);
      if (fault === "identity") {
        const wrong = JSON.parse(readFileSync(path, "utf8"));
        wrong.identity.nonce = "0".repeat(32);
        writeFileSync(path, JSON.stringify(wrong));
      }
      f.journal.save(human);
      const initial = await f.start();
      assert.equal(initial.running, true);
      assert.equal(initial.issues.available, false);
      assert.ok(initial.issues.error);
      assert.equal(initial.feedback[0].body, human.body);
      for (let i = 0; i < 5; i++) await f.tick();
      assert.equal(f.notices.length, 1);
      assert.equal(f.notices[0].kind, "issues");
      assert.equal(f.notices[0].feedback, undefined);
      await assert.rejects(
        f.watcher.reply({ replyTo: "invented", body: "No authority" }),
        /watched human/,
      );
      f.journal.save({ ...human, body: "Still delivered" });
      await f.tick();
      await f.tick();
      assert.equal(f.notices.length, 2);
      assert.equal(f.notices[1].feedback[0].body, "Still delivered");
      assert.equal(f.watcher.status().running, true);
    });
  }
});

test("Issues registers an open right pane without importing React; command focuses, releases and closes without navigation", async (t) => {
  const f = await issueHost(t);
  const spec = f.panes.get("issues");
  assert.equal(spec.title, "Issues");
  assert.equal(spec.placement, "right");
  assert.equal(spec.defaultOpen, true);
  assert.deepEqual(spec.width, { preferred: 40, min: 24, max: 56 });
  let active,
    open = true;
  f.ctx.panes = {
    open: () => {
      open = true;
    },
    close: () => {
      open = false;
    },
    isOpen: () => open,
    isVisible: () => open,
  };
  f.ctx.keyboardModes = {
    isActive: (id) => active === id,
    exitMode: () => {
      const old = active;
      active = undefined;
      f.modes.get(old)?.onExit?.();
      return true;
    },
    enterMode: (id) => {
      f.ctx.keyboardModes.exitMode();
      active = id;
      f.modes.get(id).onEnter?.(f.ctx);
      return true;
    },
  };
  const focus = () => f.commands.get("issues-pane").handler(f.ctx);
  await focus();
  assert.equal(active, "issues");
  assert.equal(f.pane.getSnapshot().focused, true);
  assert.equal(f.modes.get("issues").onKey({ name: "tab" }, f.ctx), "exit");
  f.ctx.keyboardModes.exitMode();
  assert.equal(open, true);
  await focus();
  await focus();
  assert.equal(open, false);
  assert.equal(active, undefined);
  assert.deepEqual(f.jumps, []);
});

async function paneHost(t, notes) {
  const f = await issueHost(t, notes);
  let active,
    open = true;
  const native = [];
  f.ctx.commands = {
    execute: (id) => {
      native.push(id);
      return true;
    },
  };
  f.ctx.panes = {
    open: () => {
      open = true;
    },
    close: () => {
      open = false;
    },
    isOpen: () => open,
    isVisible: () => open,
  };
  f.ctx.keyboardModes = {
    isActive: (id) => id === active,
    exitMode: () => {
      const old = active;
      active = undefined;
      f.modes.get(old)?.onExit?.(f.ctx);
      return true;
    },
    enterMode: (id) => {
      f.ctx.keyboardModes.exitMode();
      active = id;
      f.modes.get(id).onEnter?.(f.ctx);
      return true;
    },
  };
  let props = {
    reviewGeneration: "g1",
    files: [{ id: "current:7" }],
    actions: { ...f.ctx.navigation, notify: f.ctx.notify },
  };
  const commit = (patch = {}) => {
    props = { ...props, ...patch };
    f.pane.frame(props, f.pane.getSnapshot());
    return props;
  };
  const focus = async () => {
    await f.commands.get("issues-pane").handler(f.ctx);
    commit();
  };
  const key = (name, sequence = name) => {
    const result = f.modes.get(active).onKey({ name, sequence }, f.ctx);
    if (result === "exit") f.ctx.keyboardModes.exitMode();
    commit();
    return result;
  };
  const leader = async (name) => {
    const pending = f.commands.get("leader").handler(f.ctx);
    key(name);
    await pending;
    commit();
  };
  return {
    ...f,
    commit,
    focus,
    key,
    leader,
    native,
    props: () => props,
    active: () => active,
    open: () => open,
  };
}

test("Issues keyboard actions use live state before the pane frame commits", async (t) => {
  const second = { ...root, id: "user:second" };
  const third = { ...root, id: "user:third" };
  const f = await paneHost(t, [root, second, third]);
  await f.focus();
  f.events.get("note_changed")(
    { kind: "updated", note: { ...root, summary: "Updated" } },
    f.ctx,
  );
  const onKey = (name, sequence = name) =>
    f.modes.get("issues").onKey({ name, sequence }, f.ctx);

  assert.equal(onKey("j"), "handled");
  assert.equal(onKey("j"), "handled");
  assert.equal(f.pane.getSnapshot().selectedId, third.id);
  assert.equal(onKey("space", " "), "handled");
  assert.equal((await issueState(f)).items[2].status, "resolved");
  f.events.get("note_changed")({ kind: "created", note: agent }, f.ctx);
  assert.equal(onKey("k"), "handled");
  assert.equal(f.pane.getSnapshot().selectedId, second.id);
  assert.equal(onKey("return", "\\r"), "handled");
  assert.deepEqual(f.jumps, [["current:7", "new", 3]]);
});

test("Issues rows retain human creation order, mouse selects without jumping, keyboard owns movement, Space toggles and Enter explicitly goes", async (t) => {
  const second = { ...root, id: "user:second", summary: "Second body" };
  const f = await paneHost(t, [
    root,
    second,
    { ...agent, parentId: undefined },
  ]);
  await f.focus();
  assert.deepEqual(
    f.pane.getSnapshot().rows.map((r) => r.id),
    [root.id, second.id],
  );
  assert.equal(f.pane.getSnapshot().rows[0].label, "a.ts:new:3");
  assert.equal(f.pane.getSnapshot().rows[0].preview, "Fix this");
  const original = f.pane.getSnapshot();
  assert.equal(f.pane.getSnapshot(), original);
  assert.equal(f.pane.select(second.id, original, f.props()), true);
  f.commit();
  assert.deepEqual(f.jumps, []);
  for (const name of ["up", "j", "k", "down"])
    assert.equal(f.key(name), "handled");
  assert.equal(f.pane.getSnapshot().selectedId, second.id);
  assert.equal(f.key("space", " "), "handled");
  assert.equal((await issueState(f)).items[1].status, "resolved");
  assert.equal(f.pane.getSnapshot().selectedId, second.id);
  assert.deepEqual(
    f.pane.getSnapshot().rows.map((r) => r.id),
    [root.id, second.id],
  );
  assert.equal(f.key("return", "\r"), "handled");
  assert.deepEqual(f.jumps, [["current:7", "new", 3]]);
  assert.equal(f.key("space", " "), "handled");
  assert.equal((await issueState(f)).items[1].status, "open");
  assert.equal(f.key("x"), "pass");
  assert.deepEqual(f.native, []);
  assert.equal(f.key("tab"), "exit");
  assert.equal(f.open(), true);
  assert.equal(f.pane.getSnapshot().focused, false);
});

test(",i captures active Issues before comma replaces its mode; visible unfocused focuses, focused repeat closes", async (t) => {
  const f = await paneHost(t);
  await f.leader("i");
  assert.equal(f.active(), "issues");
  assert.equal(f.open(), true);
  await f.leader("i");
  assert.equal(f.active(), undefined);
  assert.equal(f.open(), false);
  await f.leader("i");
  f.ctx.keyboardModes.exitMode(); // Host-owned Escape.
  f.commit();
  assert.equal(f.open(), true);
  await f.leader("i");
  assert.equal(f.active(), "issues");
  assert.equal(f.open(), true);
  assert.deepEqual(f.jumps, []);
});

test("Issues publishes open human body edits without status revision changes; selection survives reordered snapshots and clamps on deletion", async (t) => {
  const second = { ...root, id: "user:second" },
    third = { ...root, id: "user:third" };
  const f = await paneHost(t, [root, second, third]);
  await f.focus();
  f.key("j");
  const before = f.pane.getSnapshot(),
    status = await issueState(f);
  let notifications = 0;
  const unsubscribe = f.pane.subscribe(() => notifications++);
  const edited = { ...root, summary: "Edited\nopen\x1b body" };
  f.events.get("note_changed")({ kind: "updated", note: edited }, f.ctx);
  const after = f.pane.getSnapshot();
  assert.notEqual(after, before);
  assert.equal(after.rows[0].preview, "Edited open body");
  assert.equal((await issueState(f)).revision, status.revision);
  assert.equal(notifications, 1);
  unsubscribe();
  f.set(snapshot([third, edited, second]));
  await f.pick();
  f.commit();
  assert.deepEqual(
    f.pane.getSnapshot().rows.map((r) => r.id),
    [root.id, second.id, third.id],
  );
  assert.equal(f.pane.getSnapshot().selectedId, second.id);
  f.events.get("note_changed")({ kind: "removed", note: second }, f.ctx);
  assert.equal(f.pane.getSnapshot().selectedId, third.id);
  f.events.get("note_changed")({ kind: "removed", note: third }, f.ctx);
  assert.equal(f.pane.getSnapshot().selectedId, root.id);
  f.events.get("note_changed")({ kind: "removed", note: root }, f.ctx);
  assert.equal(f.pane.getSnapshot().selectedId, undefined);
  assert.equal(Object.isFrozen(after), true);
  assert.equal(Object.isFrozen(after.rows), true);
  assert.equal(Object.isFrozen(after.rows[0]), true);
  assert.deepEqual(f.jumps, []);
});

test("Issues rejects stale frame, model revision, selection, deleted ID and unknown inventory without consulting expired commands", async (t) => {
  const f = await paneHost(t, [root, { ...root, id: "user:second" }]);
  await f.focus();
  const captured = f.pane.getSnapshot(),
    props = f.props();
  f.pane.select("user:second", captured, props);
  assert.equal(f.pane.toggle(captured, props), false);
  f.commit();
  const previous = f.pane.getSnapshot();
  f.events.get("note_changed")(
    { kind: "updated", note: { ...root, summary: "Changed" } },
    f.ctx,
  );
  assert.equal(f.pane.toggle(previous, f.props()), false);
  assert.equal(f.pane.go(previous, f.props()), false);
  f.commit();
  const beforeDelete = f.pane.getSnapshot();
  f.events.get("note_changed")(
    { kind: "removed", note: { ...root, id: "user:second" } },
    f.ctx,
  );
  assert.equal(f.pane.toggle(beforeDelete, f.props()), false);
  assert.equal(f.pane.select("user:second", beforeDelete, f.props()), false);
  f.commit();
  assert.equal(f.pane.toggle(f.pane.getSnapshot(), props), false);
  f.ctx.review.snapshot = () => {
    throw new Error("expired command");
  };
  assert.equal(f.pane.toggle(f.pane.getSnapshot(), f.props()), true);
  f.commit();
  assert.equal(f.pane.go(f.pane.getSnapshot(), f.props()), true);
  assert.equal(f.jumps.length, 1);
  assert.equal((await issueState(f)).items[0].status, "resolved");
  f.events.get("session_reload")({}, f.ctx);
  f.commit();
  assert.equal(f.pane.getSnapshot().available, false);
  assert.equal(f.pane.toggle(f.pane.getSnapshot(), f.props()), false);
  assert.equal(f.pane.go(f.pane.getSnapshot(), f.props()), false);
  assert.equal(f.jumps.length, 1);
});

test("Issues frame generation mismatch remains unavailable until a fresh command reconciles, with conservative Go after reload and ID-only resolution", async (t) => {
  const f = await paneHost(t);
  assert.equal(f.pane.getSnapshot().available, false);
  f.commit();
  assert.deepEqual(f.pane.getSnapshot().rows, []);
  await f.focus();
  const old = f.pane.getSnapshot(),
    props = f.props();
  f.commit({ reviewGeneration: "g2", files: [{ id: "new:2" }] });
  assert.equal(f.pane.getSnapshot().available, false);
  assert.equal((await issueState(f)).available, false);
  assert.equal(f.pane.toggle(old, props), false);
  f.commit({ reviewGeneration: "g1" });
  assert.equal(f.pane.toggle(f.pane.getSnapshot(), f.props()), false);
  const next = snapshot([root], "g2");
  next.files[0].runtimeId = "new:2";
  f.set(next);
  f.commit({ reviewGeneration: "g2" });
  f.ctx.keyboardModes.exitMode();
  await f.focus();
  assert.equal(f.pane.getSnapshot().available, true);
  assert.equal(f.pane.getSnapshot().rows[0].locationVerified, false);
  assert.equal(f.pane.go(f.pane.getSnapshot(), f.props()), false);
  assert.match(f.toasts.at(-1)[0], /unverified/);
  assert.equal(f.pane.toggle(f.pane.getSnapshot(), f.props()), true);
  assert.equal((await issueState(f)).open, 0);
  assert.deepEqual(f.jumps, []);
});

test("Issues Go uses only current visible files and refuses stale, orphaned or missing anchors; status remains actionable by ID", async (t) => {
  const f = await paneHost(t);
  await f.focus();
  const before = f.pane.getSnapshot();
  const oldProps = f.props();
  f.commit({ files: [] });
  assert.equal(f.pane.go(before, oldProps), false);
  assert.equal(f.pane.go(f.pane.getSnapshot(), f.props()), false);
  assert.match(f.toasts.at(-1)[0], /hidden/);
  for (const patch of [
    { resolution: "stale" },
    { resolution: "orphaned" },
    { anchor: {} },
  ]) {
    f.events.get("note_changed")(
      { kind: "updated", note: { ...root, ...patch } },
      f.ctx,
    );
    f.commit({ files: [{ id: "current:7" }] });
    assert.equal(f.pane.go(f.pane.getSnapshot(), f.props()), false);
    assert.equal(f.pane.toggle(f.pane.getSnapshot(), f.props()), true);
  }
  assert.deepEqual(f.jumps, []);
});

test("Issues hides unknown counts after index failure, releases mode on unmount/reload/shutdown and preserves selection across hide/show", async (t) => {
  const f = await paneHost(t, [root, { ...root, id: "user:second" }]);
  await f.focus();
  f.key("j");
  f.pane.unmount();
  assert.equal(f.active(), undefined);
  assert.equal(f.pane.getSnapshot().selectedId, "user:second");
  await f.focus();
  assert.equal(f.pane.getSnapshot().selectedId, "user:second");
  f.events.get("session_reload")({}, f.ctx);
  assert.equal(f.active(), undefined);
  assert.equal(f.pane.getSnapshot().available, false);
  assert.deepEqual(f.pane.getSnapshot().rows, []);
  await f.focus();
  chmodSync(f.dir, 0o500);
  try {
    assert.equal(f.pane.toggle(f.pane.getSnapshot(), f.props()), false);
    assert.equal(f.pane.getSnapshot().available, false);
    assert.deepEqual(f.pane.getSnapshot().rows, []);
    assert.match(f.toasts.at(-1)[0], /unavailable/i);
  } finally {
    chmodSync(f.dir, 0o700);
  }
  f.ctx.keyboardModes.exitMode();
  await f.focus();
  assert.equal(f.pane.getSnapshot().available, true);
  f.events.get("shutdown")({}, f.ctx);
  assert.equal(f.active(), undefined);
  assert.deepEqual(f.native, []);
});

test("Issues factory instances isolate inventories, selection and subscriptions; long lists reveal the selected stable row", async (t) => {
  const notes = Array.from({ length: 300 }, (_, i) => ({
    ...root,
    id: `user:${i}`,
  }));
  const a = await paneHost(t, notes),
    b = await paneHost(t, [{ ...root, id: "user:other" }]);
  await a.focus();
  await b.focus();
  const bState = b.pane.getSnapshot();
  for (let i = 0; i < 350; i++) a.key("j");
  assert.equal(a.pane.getSnapshot().selectedId, "user:299");
  const { followIssueSelection, issueRowId } =
    await import("./review/hunk/pane.mjs");
  let top = 0;
  const scroll = {
    scrollChildIntoView(id) {
      const index = notes.findIndex((note) => issueRowId(note.id) === id);
      const row = index * 3;
      if (row < top) top = row;
      else if (row + 3 > top + 12) top = row + 3 - 12;
    },
  };
  followIssueSelection(scroll, a.pane.getSnapshot().selectedId);
  assert.equal(top, 888);
  for (let i = 0; i < 350; i++) a.key("k");
  followIssueSelection(scroll, a.pane.getSnapshot().selectedId);
  assert.equal(top, 0);
  assert.equal(b.pane.getSnapshot(), bState);
  assert.deepEqual(a.jumps, []);
});

test("Issues passes modified native keys and host-owned shortcuts without moving or toggling", async (t) => {
  const f = await paneHost(t);
  await f.focus();
  const before = f.pane.getSnapshot();
  for (const modifier of ["shift", "ctrl", "meta", "option"]) {
    for (const name of ["down", "up", "space", "return"]) {
      assert.equal(
        f.modes
          .get("issues")
          .onKey({ name, sequence: name, [modifier]: true }, f.ctx),
        "pass",
      );
    }
  }
  for (const sequence of ["n", "o", "r", "u", "/", "q", ","]) {
    assert.equal(
      f.modes.get("issues").onKey({ name: sequence, sequence }, f.ctx),
      "pass",
    );
  }
  assert.equal(f.pane.getSnapshot(), before);
  assert.deepEqual(f.jumps, []);
  assert.deepEqual(f.native, []);
});

test("Issues selection following waits for layout, rearms on resize, and leaves mouse scrolling independent", async () => {
  const { watchIssueSelection } = await import("./review/hunk/pane.mjs");
  const events = new Map(),
    revealed = [];
  const scroll = {
    viewport: {
      height: 0,
      on: (name, handler) => events.set(name, handler),
      off: (name, handler) => {
        if (events.get(name) === handler) events.delete(name);
      },
    },
    scrollChildIntoView: (id) => {
      revealed.push(id);
      events.get("layout-changed")?.(); // Reentrant layout notification.
    },
  };
  const stop = watchIssueSelection(scroll, "user:299");
  assert.deepEqual(revealed, []);
  scroll.viewport.height = 12;
  events.get("layout-changed")();
  assert.deepEqual(revealed, ["issue-user%3A299"]);
  events.get("layout-changed")(); // Mouse scrolling must not snap back.
  assert.equal(revealed.length, 1);
  events.get("resized")();
  assert.equal(revealed.length, 2);
  stop();
  assert.equal(events.size, 0);
});
