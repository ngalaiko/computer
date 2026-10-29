import assert from "node:assert/strict";
import { realpathSync } from "node:fs";
import test from "node:test";
import { registerOyoWatch } from "./oyo-review/watch.mjs";

// Confirmed seams: native CLI snapshots → feedback; public Pi host → delivery/lifecycle.
const workspace = realpathSync(new URL("../../..", import.meta.url).pathname);
const change = "abcdefghijklmnopqrstuvwxabcdefghijklmnop";
const key = "jj:change:workspace:abcdefgh";
const human = (id, body, extra = {}) => ({
  id,
  body,
  file: "example.ts",
  kind: "line",
  resolved: false,
  outdated: false,
  ...extra,
});
const Type = new Proxy(
  {},
  {
    get:
      () =>
      (...args) =>
        args,
  },
);

function fixture(t) {
  const f = {
    comments: [],
    messages: [],
    calls: [],
    timers: new Set(),
    handlers: {},
    control: {
      name: "review-exact",
      pid: 123,
      workspace,
      target: "@",
      socket: "/tmp/review.sock",
      createdAt: "stamp",
    },
    status: {
      workspaceRoot: workspace,
      reviewKey: key,
      target: "working tree",
      label: "working tree",
    },
    change,
    responseSession: "review-exact",
    commentKey: key,
  };
  const pi = {
    registerTool(tool) {
      f.tool = tool;
    },
    on(name, handler) {
      f.handlers[name] = handler;
    },
    async sendMessage(message, options) {
      if (f.notifyError) throw new Error("notify failed");
      f.messages.push({ ...message, options });
    },
  };
  const exec = async (bin, args, options) => {
    f.calls.push({ bin, args, options });
    if (f.intercept) {
      const result = await f.intercept(bin, args, options);
      if (result) return result;
    }
    let value;
    if (args[0] === "root") value = workspace;
    else if (args[0] === "log") value = f.change;
    else if (args[0] === "control")
      value = { ok: true, session: f.responseSession, data: f.control };
    else if (args[1] === "status") value = f.status;
    else if (args[1] === "comment")
      value = {
        version: 1,
        reviewKey: f.commentKey,
        target: "working tree",
        label: "working tree",
        comments: f.comments,
      };
    else throw new Error(`unexpected CLI ${args}`);
    return {
      code: 0,
      killed: false,
      stdout: typeof value === "string" ? value : JSON.stringify(value),
      stderr: "",
    };
  };
  registerOyoWatch(pi, Type, {
    exec,
    schedule(callback) {
      f.timers.add(callback);
      return callback;
    },
    cancel(callback) {
      f.timers.delete(callback);
    },
  });
  f.act = (action, extra = {}) => f.tool.execute("test", { action, ...extra });
  f.start = () =>
    f.act("start", {
      workspace,
      session: "review-exact",
      oyBin: process.execPath,
      jjBin: process.execPath,
    });
  f.tick = async () => {
    assert.equal(f.timers.size, 1, "one nonoverlapping scheduled poll");
    const callback = [...f.timers][0];
    f.timers.delete(callback);
    await callback();
  };
  f.statusResult = async () => (await f.act("status")).details;
  t.after(() => f.act("stop"));
  return f;
}

test("explicit start returns a baseline; saved untyped feedback wakes only its parent once", async (t) => {
  const f = fixture(t);
  assert.equal(f.calls.length, 0);
  assert.equal(f.timers.size, 0);
  assert.equal(f.tool.name, "oyo_watch");
  assert.equal(f.tool.executionMode, "sequential");
  f.comments = [human(1, "Already saved")];
  const initial = (await f.start()).details;
  assert.equal(initial.running, true);
  assert.equal(initial.available, true);
  assert.equal(initial.feedback[0].body, "Already saved");
  assert.equal(initial.feedback[0].provenance, "human-or-untyped");
  assert.deepEqual(initial.issues, { open: 1, resolved: 0 });
  const commentReads = f.calls.filter((call) => call.args[1] === "comment");
  assert.equal(commentReads.length, 1);
  assert.deepEqual(commentReads[0].args, [
    "review",
    "comment",
    "-t",
    "@",
    "--json",
  ]);
  assert.equal(f.messages.length, 0);
  f.comments.push(human(2, "Please test this"));
  await f.tick();
  assert.equal(f.messages.length, 1);
  const message = f.messages[0];
  assert.equal(message.customType, "oyo-watch");
  assert.equal(message.display, true);
  assert.deepEqual(message.options, {
    triggerTurn: true,
    deliverAs: "followUp",
  });
  assert.equal(message.details.event.kind, "feedback");
  assert.equal(message.details.event.changes[0].action, "added");
  assert.equal(
    message.details.event.changes[0].comment.body,
    "Please test this",
  );
  assert.ok(message.content.includes("Please test this"));
  await f.tick();
  assert.equal(f.messages.length, 1);
  for (const call of f.calls) {
    assert.equal(call.options.cwd, workspace);
    assert.ok(call.options.signal instanceof AbortSignal);
    assert.ok(call.options.timeout > 0);
    if (call.args[0] === "control")
      assert.deepEqual(call.args, [
        "control",
        "get",
        "--session",
        "review-exact",
        "--json",
      ]);
    if (call.args[0] === "review") assert.ok(call.args.includes("@"));
  }
});

test("full snapshots reconcile edits/deletions and root toggles without agent or anchor echo", async (t) => {
  const f = fixture(t);
  f.comments = [
    human(1, "Root"),
    human(2, "Reply", { inReplyTo: 1 }),
    human(3, "Agent", { author: { authorType: "agent" } }),
    human(4, "Stale", { outdated: true, resolved: true }),
  ];
  await f.start();
  f.comments[0] = {
    ...f.comments[0],
    body: "Edited",
    updatedAt: "same-second",
    anchorSnapshot: { newFile: "large", oldFile: "large" },
  };
  await f.tick();
  assert.equal(f.messages[0].details.event.changes[0].action, "edited");
  assert.equal(f.messages[0].details.event.changes[0].comment.body, "Edited");
  assert.ok(!JSON.stringify(f.messages[0]).includes("newFile"));
  f.comments[0].body = "Edited again";
  await f.tick();
  assert.equal(
    f.messages[1].details.event.changes[0].comment.body,
    "Edited again",
  );
  f.comments[0].resolved = true;
  f.comments[1].resolved = true;
  await f.tick();
  assert.deepEqual(f.messages[2].details.event, {
    kind: "issues",
    threads: [{ id: 1, resolved: true }],
    issues: { open: 1, resolved: 2 },
    actor: "unknown",
  });
  assert.ok(!f.messages[2].content.includes("Edited again"));
  f.comments[0].resolved = false;
  f.comments[1].resolved = false;
  await f.tick();
  assert.deepEqual(f.messages[3].details.event.threads, [
    { id: 1, resolved: false },
  ]);
  assert.deepEqual((await f.statusResult()).issues, { open: 2, resolved: 1 });
  f.comments[0] = {
    ...f.comments[0],
    updatedAt: "later",
    file: "renamed.ts",
    outdated: true,
    author: { authorType: "human", name: "Renamed" },
    newRange: { start: 9, end: 9 },
    oldRange: null,
    side: "new",
  };
  f.comments[2].body = "Agent edit";
  f.comments.push(human(5, "Bot", { author: { authorType: "bot" } }));
  await f.tick();
  f.comments = f.comments.filter((c) => c.id !== 3 && c.id !== 5);
  await f.tick();
  assert.equal(
    f.messages.length,
    4,
    "no metadata, reanchor, or agent-only count wakeup",
  );
  f.comments = f.comments.filter((c) => ![1, 2].includes(c.id));
  await f.tick();
  assert.deepEqual(
    f.messages[4].details.event.changes.map((c) => [
      c.action,
      c.comment.id,
      c.comment.rootId,
    ]),
    [
      ["deleted", 1, 1],
      ["deleted", 2, 1],
    ],
  );
  assert.equal(f.messages[4].details.event.actor, "unknown");
  await f.tick();
  assert.equal(f.messages.length, 5);
});

for (const [name, alter] of [
  [
    "response session",
    (f) => {
      f.responseSession = "other";
    },
  ],
  [
    "metadata name",
    (f) => {
      f.control.name = "other";
    },
  ],
  [
    "workspace",
    (f) => {
      f.control.workspace = "/tmp";
    },
  ],
  [
    "target",
    (f) => {
      f.control.target = "bookmark";
    },
  ],
  [
    "PID replacement",
    (f) => {
      f.control.pid++;
    },
  ],
  [
    "socket replacement",
    (f) => {
      f.control.socket += "new";
    },
  ],
  [
    "empty createdAt",
    (f) => {
      f.control.createdAt = "";
    },
  ],
  [
    "missing createdAt",
    (f) => {
      delete f.control.createdAt;
    },
  ],
  [
    "object createdAt",
    (f) => {
      f.control.createdAt = {};
    },
  ],
  [
    "status cwd",
    (f) => {
      f.status.workspaceRoot = "/tmp";
    },
  ],
  [
    "status target",
    (f) => {
      f.status.target = "stack";
    },
  ],
  [
    "review key",
    (f) => {
      f.status.reviewKey = "jj:change:workspace:zzzzzzzz";
    },
  ],
  [
    "comment key",
    (f) => {
      f.commentKey = "other";
    },
  ],
  [
    "stable change",
    (f) => {
      f.change = "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz";
    },
  ],
]) {
  test(`identity mismatch (${name}) stops immediately, without reading another session`, async (t) => {
    const f = fixture(t);
    await f.start();
    alter(f);
    await f.tick();
    const status = await f.statusResult();
    assert.equal(status.running, false);
    assert.equal(status.available, false);
    assert.equal(status.issues, null);
    assert.match(status.error, /identity/i);
    assert.equal(f.messages.length, 1);
    assert.equal(f.messages[0].details.event.kind, "error");
    assert.equal(f.timers.size, 0);
  });
}

test("createdAt refresh between polls preserves feedback delivery", async (t) => {
  const f = fixture(t);
  f.control.createdAt = 100;
  await f.start();
  f.control.createdAt = 101;
  f.comments = [human(1, "Please retest")];
  await f.tick();
  assert.equal(f.messages.length, 1);
  assert.equal(f.messages[0].details.event.kind, "feedback");
  assert.ok(f.messages[0].content.includes("Please retest"));
  let status = await f.statusResult();
  assert.equal(status.running, true);
  assert.equal(status.available, true);
  assert.equal(status.error, null);
  await f.tick();
  assert.equal(f.messages.length, 1);
  status = await f.statusResult();
  assert.equal(status.running, true);
  assert.equal(status.available, true);
  assert.equal(status.error, null);
});

test("createdAt refresh within a snapshot preserves feedback delivery", async (t) => {
  const f = fixture(t);
  f.control.createdAt = 100;
  await f.start();
  let reads = 0;
  f.intercept = async (_bin, args) => {
    if (args[0] === "control" && ++reads === 2) f.control.createdAt = 101;
  };
  f.comments = [human(1, "Please retest")];
  await f.tick();
  assert.equal(reads, 2);
  assert.equal(f.messages.length, 1);
  assert.equal(f.messages[0].details.event.kind, "feedback");
  assert.ok(f.messages[0].content.includes("Please retest"));
  let status = await f.statusResult();
  assert.equal(status.running, true);
  assert.equal(status.available, true);
  assert.equal(status.error, null);
  await f.tick();
  assert.equal(f.messages.length, 1);
  status = await f.statusResult();
  assert.equal(status.running, true);
  assert.equal(status.available, true);
  assert.equal(status.error, null);
});

test("identity bounds a snapshot; ordinary edits preserve the pinned stable change", async (t) => {
  const f = fixture(t);
  await f.start();
  const identity = (await f.statusResult()).identity;
  assert.equal(identity.changeId, change);
  assert.equal(identity.pid, 123);
  f.status.diffFingerprint = "amended";
  f.comments = [human(1, "After ordinary edit")];
  await f.tick();
  assert.equal(f.messages.length, 1);
  let reads = 0;
  f.intercept = async (_bin, args) => {
    if (args[0] === "control" && ++reads === 2) f.control.pid++;
  };
  f.comments.push(human(2, "Wrong snapshot"));
  await f.tick();
  assert.equal(f.messages.length, 2);
  assert.equal(f.messages[1].details.event.kind, "error");
  assert.ok(!f.messages[1].content.includes("Wrong snapshot"));
  const logs = f.calls.filter((c) => c.args[0] === "log");
  assert.ok(
    logs.some((c) => c.args[2] === "abcdefgh"),
    "native short change prefix is resolved unambiguously",
  );
  assert.ok(
    logs.filter((c) => c.args[2] === "@").length >= 6,
    "stable change checked before and after each snapshot",
  );
});

for (const [name, output] of [
  [
    "truncated JSON",
    { code: 0, stdout: '{"comments":[', stderr: "", killed: false },
  ],
  ["timeout", { code: -1, stdout: "", stderr: "", killed: true }],
  ["CLI error", { code: 1, stdout: "", stderr: "bad", killed: false }],
  [
    "missing comments",
    {
      code: 0,
      stdout: JSON.stringify({
        version: 1,
        reviewKey: key,
        target: "working tree",
      }),
      stderr: "",
      killed: false,
    },
  ],
  [
    "invalid comments",
    {
      code: 0,
      stdout: JSON.stringify({
        version: 1,
        reviewKey: key,
        target: "working tree",
        comments: [human(1, 42)],
      }),
      stderr: "",
      killed: false,
    },
  ],
  [
    "malformed author",
    {
      code: 0,
      stdout: JSON.stringify({
        version: 1,
        reviewKey: key,
        target: "working tree",
        comments: [human(1, "Changed", { author: "agent" })],
      }),
      stderr: "",
      killed: false,
    },
  ],
  [
    "duplicate IDs",
    {
      code: 0,
      stdout: JSON.stringify({
        version: 1,
        reviewKey: key,
        target: "working tree",
        comments: [human(1, "a"), human(1, "b")],
      }),
      stderr: "",
      killed: false,
    },
  ],
]) {
  test(`${name} is unavailable, never a deletion; bounded retries stop and notify once`, async (t) => {
    const f = fixture(t);
    f.comments = [human(1, "Preserved")];
    await f.start();
    f.intercept = async (_bin, args) =>
      args[1] === "comment" ? output : undefined;
    await f.tick();
    assert.equal((await f.statusResult()).available, false);
    assert.equal((await f.statusResult()).issues, null);
    assert.equal(f.messages.length, 0);
    await f.tick();
    await f.tick();
    assert.equal((await f.statusResult()).running, false);
    assert.equal(f.messages.length, 1);
    assert.equal(f.messages[0].details.event.kind, "error");
    assert.ok(!f.messages[0].content.includes('"deleted"'));
    assert.equal(f.timers.size, 0);
  });
}

test("transient read failure keeps the delivered baseline", async (t) => {
  const f = fixture(t);
  f.comments = [human(1, "Before")];
  await f.start();
  f.intercept = async () => {
    throw new Error("temporarily unavailable");
  };
  await f.tick();
  f.intercept = null;
  f.comments[0].body = "After";
  await f.tick();
  assert.equal(f.messages[0].details.event.changes[0].action, "edited");
  assert.equal((await f.statusResult()).available, true);
});

test("failed delivery retries the observed snapshot before observing later updates", async (t) => {
  const f = fixture(t);
  await f.start();
  f.comments = [human(1, "Observed")];
  f.notifyError = true;
  await f.tick();
  assert.equal(f.messages.length, 0);
  f.comments = [human(1, "Later")];
  f.notifyError = false;
  await f.tick();
  assert.equal(f.messages[0].details.event.changes[0].comment.body, "Observed");
  await f.tick();
  assert.equal(f.messages[1].details.event.changes[0].comment.body, "Later");
  await f.tick();
  assert.equal(f.messages.length, 2);
});

test("oversized feedback stops explicitly instead of silently truncating", async (t) => {
  const f = fixture(t);
  await f.start();
  f.comments = [
    human(1, "x".repeat(60_000)),
    human(2, "y".repeat(60_000)),
    human(3, "z".repeat(60_000)),
  ];
  await f.tick();
  assert.equal((await f.statusResult()).running, false);
  assert.match((await f.statusResult()).error, /payload limit/i);
  assert.equal(f.messages[0].details.event.kind, "error");
});

for (const lifecycle of ["stop", "reload", "tree"]) {
  test(`${lifecycle} aborts pending CLI and fences late completion; restart is an explicit baseline`, async (t) => {
    const f = fixture(t);
    await f.start();
    const staleTimer = [...f.timers][0];
    let release, entered;
    const waiting = new Promise((resolve) => {
      entered = resolve;
    });
    const blocked = new Promise((resolve) => {
      release = resolve;
    });
    let signal;
    f.intercept = async (_bin, args, options) => {
      if (args[0] === "control") {
        signal = options.signal;
        entered();
        await blocked;
      }
    };
    const poll = f.tick();
    await waiting;
    const stopping =
      lifecycle === "stop"
        ? f.act("stop")
        : lifecycle === "reload"
          ? f.handlers.session_shutdown({ reason: "reload" })
          : f.handlers.session_tree({});
    assert.equal(signal.aborted, true);
    f.comments = [human(1, "Saved while stopped")];
    release();
    await stopping;
    await poll;
    assert.equal(f.messages.length, 0);
    assert.equal(f.timers.size, 0);
    const calls = f.calls.length;
    await staleTimer();
    assert.equal(
      f.calls.length,
      calls,
      "a canceled timer cannot spawn another CLI",
    );
    assert.equal((await f.statusResult()).running, false);
    assert.equal((await f.statusResult()).available, false);
    f.intercept = null;
    const restarted = (await f.start()).details;
    assert.equal(restarted.feedback[0].body, "Saved while stopped");
    assert.equal(f.messages.length, 0);
    await f.tick();
    assert.equal(f.messages.length, 0);
  });
}

test("shutdown during startup fences activation, including filesystem validation awaits", async (t) => {
  const f = fixture(t);
  const startup = f.start();
  await f.handlers.session_shutdown({ reason: "reload" });
  await assert.rejects(startup, /stopped|canceled/i);
  assert.equal(f.timers.size, 0);
  assert.equal((await f.statusResult()).running, false);
});

test("separate parent hosts never share delivery or shutdown state", async (t) => {
  const a = fixture(t),
    b = fixture(t);
  await a.start();
  await b.start();
  a.comments = [human(1, "Only A")];
  await a.tick();
  await b.tick();
  assert.equal(a.messages.length, 1);
  assert.equal(b.messages.length, 0);
  await a.handlers.session_shutdown({ reason: "new" });
  b.comments = [human(2, "Only B")];
  await b.tick();
  assert.equal(b.messages[0].details.event.changes[0].comment.body, "Only B");
});

test("a pending delivery cannot cross session replacement", async (t) => {
  const f = fixture(t);
  await f.start();
  f.comments = [human(1, "Pending")];
  f.notifyError = true;
  await f.tick();
  f.notifyError = false;
  f.control.pid++;
  await f.tick();
  assert.equal(f.messages.length, 1);
  assert.equal(f.messages[0].details.event.kind, "error");
  assert.ok(!f.messages[0].content.includes('"body"'));
  assert.equal((await f.statusResult()).pendingDelivery, true);
});

test("permanent delivery failure is visible in status and stops after three attempts", async (t) => {
  const f = fixture(t);
  await f.start();
  f.notifyError = true;
  f.comments = [human(1, "Undelivered")];
  await f.tick();
  await f.tick();
  await f.tick();
  const status = await f.statusResult();
  assert.equal(status.running, false);
  assert.equal(status.pendingDelivery, true);
  assert.match(status.error, /notify failed/);
  assert.equal(f.timers.size, 0);
});

for (const [name, extra] of [
  ["implicit session", { session: undefined }],
  ["relative executable", { oyBin: "oy" }],
  ["relative workspace", { workspace: "." }],
  ["relative JJ", { jjBin: "jj" }],
  [
    "unexecutable Oyo",
    { oyBin: new URL("./oyo-review.test.mjs", import.meta.url).pathname },
  ],
  ["oversized session", { session: "x".repeat(300) }],
]) {
  test(`start rejects ${name} before spawning`, async (t) => {
    const f = fixture(t);
    await assert.rejects(
      f.act("start", {
        workspace,
        session: "review-exact",
        oyBin: process.execPath,
        jjBin: process.execPath,
        ...extra,
      }),
    );
    assert.equal(f.calls.length, 0);
    assert.equal(f.timers.size, 0);
  });
}

test("stable change and JJ root are checked even when Oyo metadata looks correct", async (t) => {
  const f = fixture(t);
  await f.start();
  f.intercept = async (_bin, args) =>
    args[0] === "root"
      ? { code: 0, killed: false, stdout: "/tmp", stderr: "" }
      : undefined;
  await f.tick();
  assert.equal((await f.statusResult()).running, false);
});

test("native full snapshot preserves outdated counts and comment locations", async (t) => {
  const f = fixture(t);
  f.comments = [
    human(1, "Active"),
    human(2, "Stale", {
      outdated: true,
      newRange: { start: 3, end: 4 },
      oldRange: { start: 7, end: 8 },
      side: "old",
    }),
  ];
  const initial = (await f.start()).details;
  assert.deepEqual(initial.issues, { open: 2, resolved: 0 });
  assert.deepEqual(initial.feedback[1], {
    id: 2,
    rootId: 2,
    body: "Stale",
    file: "example.ts",
    kind: "line",
    inReplyTo: undefined,
    newRange: { start: 3, end: 4 },
    oldRange: { start: 7, end: 8 },
    side: "old",
    resolved: false,
    outdated: true,
    provenance: "human-or-untyped",
  });
  f.comments[1].body = "Edited stale";
  await f.tick();
  assert.equal(f.messages[0].details.event.changes[0].action, "edited");
  assert.deepEqual(f.messages[0].details.event.changes[0].comment.oldRange, {
    start: 7,
    end: 8,
  });
  f.comments = f.comments.filter((c) => c.id !== 2);
  await f.tick();
  assert.deepEqual(
    f.messages[1].details.event.changes.map((c) => [c.action, c.comment.id]),
    [["deleted", 2]],
  );
});

test("malformed native ranges fail without fabricating deletion", async (t) => {
  const f = fixture(t);
  f.comments = [human(1, "Preserved")];
  await f.start();
  f.comments = [human(1, "Preserved", { newRange: { start: 0, end: 1 } })];
  await f.tick();
  assert.equal((await f.statusResult()).available, false);
  assert.equal(f.messages.length, 0);
  await f.tick();
  await f.tick();
  assert.equal(f.messages[0].details.event.kind, "error");
  assert.ok(!f.messages[0].content.includes('"deleted"'));
});

for (const extra of [
  { session: null },
  { workspace: "/nonexistent/oyo-workspace" },
  { oyBin: "/nonexistent/oy" },
  { jjBin: "/nonexistent/jj" },
]) {
  test(`invalid replacement preserves active delivery: ${JSON.stringify(extra)}`, async (t) => {
    const f = fixture(t);
    await f.start();
    await assert.rejects(
      f.act("start", {
        workspace,
        session: "review-exact",
        oyBin: process.execPath,
        jjBin: process.execPath,
        ...extra,
      }),
    );
    assert.equal((await f.statusResult()).running, true);
    f.comments = [human(1, "Still delivering")];
    await f.tick();
    assert.equal(
      f.messages[0].details.event.changes[0].comment.body,
      "Still delivering",
    );
  });
}

test("canceled tree navigation preserves delivery; actual lifecycle stops expose a reason", async (t) => {
  const f = fixture(t);
  await f.start();
  await f.handlers.session_before_tree?.({});
  assert.equal((await f.statusResult()).running, true);
  f.comments = [human(1, "After canceled navigation")];
  await f.tick();
  assert.equal(f.messages.length, 1);
  await f.handlers.session_tree({});
  assert.equal((await f.statusResult()).stoppedReason, "session_tree");
  assert.equal((await f.statusResult()).error, null);
  await f.start();
  await f.handlers.session_shutdown({ reason: "reload" });
  assert.equal((await f.statusResult()).stoppedReason, "session_shutdown");
  assert.equal(f.messages.length, 1);
  await f.start();
  await f.act("stop");
  assert.equal((await f.statusResult()).stoppedReason, "explicit");
});

test("provider-backed untyped bodies never echo; roots and unknown status actors remain", async (t) => {
  const f = fixture(t);
  f.comments = [
    human(1, "Provider bot", {
      provider: { name: "github", payload: "discard-me" },
    }),
  ];
  const initial = (await f.start()).details;
  assert.deepEqual(initial.feedback, []);
  assert.deepEqual(initial.issues, { open: 1, resolved: 0 });
  f.comments[0].body = "Provider edit";
  f.comments.push(human(2, "Provider new", { provider: {} }));
  await f.tick();
  f.comments.pop();
  await f.tick();
  assert.equal(f.messages.length, 0);
  f.comments[0].resolved = true;
  await f.tick();
  assert.equal(f.messages[0].details.event.kind, "issues");
  assert.equal(f.messages[0].details.event.actor, "unknown");
  assert.ok(!JSON.stringify(f.messages).includes("discard-me"));
  f.comments = [human(3, "Local untyped")];
  await f.tick();
  assert.deepEqual(
    f.messages[1].details.event.changes.map((c) => c.comment.body),
    ["Local untyped"],
  );
});

for (const replacement of ["root", "reviewKey"]) {
  test(`pending retry revalidates ${replacement} without delivering or deleting the old batch`, async (t) => {
    const f = fixture(t);
    await f.start();
    f.comments = [human(1, "Pending private body")];
    f.notifyError = true;
    await f.tick();
    assert.equal((await f.statusResult()).issues, null);
    f.notifyError = false;
    f.comments = [];
    if (replacement === "root") f.status.workspaceRoot = "/tmp";
    else f.status.reviewKey = f.commentKey = "jj:change:replacement:abcdefgh";
    await f.tick();
    const status = await f.statusResult();
    assert.equal(status.running, false);
    assert.equal(status.pendingDelivery, true);
    assert.equal(status.issues, null);
    assert.deepEqual(
      f.messages.map((m) => m.details.event.kind),
      ["error"],
    );
    assert.ok(!JSON.stringify(f.messages).includes("Pending private body"));
  });
}

test("newer startup fences an older startup awaiting filesystem validation", async (t) => {
  const f = fixture(t);
  const older = assert.rejects(f.start(), /canceled|stopped/i);
  const newer = f.start();
  await older;
  assert.equal((await newer).details.running, true);
  assert.equal(f.timers.size, 1);
  f.comments = [human(1, "Newest watch")];
  await f.tick();
  assert.equal(f.messages.length, 1);
});
