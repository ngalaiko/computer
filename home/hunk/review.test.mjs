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
  const f = fixture(t);
  f.journal.close();
  const { default: factory } = await import("./review/hunk/index.ts");
  const events = new Map(),
    commands = new Map(),
    modes = new Map(),
    statuses = new Map(),
    toasts = [];
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
      registerKeyboardMode: (mode) => modes.set(mode.id, mode),
      on: (id, handler) => events.set(id, handler),
      registerCommand: (command, handler) =>
        commands.set(command.id, { ...command, handler }),
    },
    { stateDir: f.dir },
  );
  events.get("startup")({ cwd: f.dir }, ctx);
  t.after(() => events.get("shutdown")({}, ctx));
  return { ...f, events, commands, modes, ctx, statuses, toasts };
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
    "--focus",
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
    const call = (params) =>
      tools.get("hunk_watch").execute("id", params, undefined, undefined, {});
    await call({
      action: "start",
      workspace: f.dir,
      session: "native-exact",
      hunkBin: process.execPath,
    });
    f.journal.save(human);
    f.journal.close();
    await timer();
    assert.equal(messages.length, 1);
    assert.equal(messages[0].message.customType, "hunk-watch");
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
  const { default: factory } = await import("./review/hunk/index.ts");
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
