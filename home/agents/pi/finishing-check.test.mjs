import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const script = fileURLToPath(
  new URL("./skills/feature/scripts/finishing-check.mjs", import.meta.url),
);
const flags = ["--no-pager", "--color=never"];
const pinTemplate = '"[" ++ json(commit_id) ++ "," ++ json(change_id) ++ "]"';

function jj(cwd, ...args) {
  const result = spawnSync("jj", [...flags, ...args], {
    cwd,
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr || result.error?.message);
  return result.stdout.trim();
}

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "finishing-check-")));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const source = join(root, "source");
  jj(root, "git", "init", source);
  jj(source, "config", "set", "--repo", "user.name", "Test");
  jj(source, "config", "set", "--repo", "user.email", "test@example.com");
  const pin = (workspace) => {
    const [commit, change] = JSON.parse(
      jj(
        workspace,
        "--ignore-working-copy",
        "log",
        "-G",
        "-r",
        "@",
        "-T",
        pinTemplate,
      ),
    );
    return { workspace, commit, change };
  };
  const manifest = {
    version: 1,
    operation: "integration",
    snapshots: [pin(source)],
  };
  const run = (value = manifest, env = process.env) => {
    const path = join(root, "manifest.json");
    writeFileSync(
      path,
      typeof value === "string" ? value : JSON.stringify(value),
    );
    return spawnSync(process.execPath, [script, path], {
      cwd: root,
      encoding: "utf8",
      env,
    });
  };
  const cleanup = () => {
    const cleanupRoot = join(root, "workers");
    mkdirSync(cleanupRoot);
    const worker = join(cleanupRoot, "worker");
    const coordinator = join(root, "coordinator");
    jj(source, "workspace", "add", "--name", "worker", worker);
    jj(source, "workspace", "add", "--name", "coordinator", coordinator);
    jj(worker, "bookmark", "create", "scratch/worker", "-r", "@");
    manifest.operation = "cleanup";
    manifest.snapshots.push(pin(worker), pin(coordinator));
    manifest.cleanup = {
      root: cleanupRoot,
      protectedWorkspaces: [source, coordinator],
      workspaces: [{ name: "worker", path: worker }],
      bookmarks: ["scratch/worker"],
      revisions: [pin(worker).commit],
    };
    return { worker, coordinator, cleanupRoot };
  };
  return { root, source, pin, manifest, run, cleanup };
}

function checked(result) {
  assert.equal(result.status, 0, result.stderr);
  const output = JSON.parse(result.stdout);
  assert.equal(output.status, "checked");
  for (const term of [
    "approval",
    "ownership",
    "process termination",
    "redundancy",
    "content equivalence",
  ]) {
    assert.ok(
      output.limitations.some((line) => line.includes(term)),
      term,
    );
  }
  return output;
}

function refused(result, message) {
  assert.notEqual(result.status, 0, result.stdout);
  assert.equal(result.stdout, "");
  assert.match(result.stderr, message);
}

test("integration rechecks full snapshot pins and reports coordinator limitations", (t) => {
  const f = fixture(t);
  const output = checked(f.run());
  assert.equal(output.operation, "integration");
  assert.deepEqual(output.snapshots, f.manifest.snapshots);
  assert.equal(Object.hasOwn(output, "cleanup"), false);
});

test("cleanup validates exact workspace, bookmark and revision lists without acting", (t) => {
  const f = fixture(t);
  const { worker } = f.cleanup();
  const before = jj(
    f.source,
    "--ignore-working-copy",
    "op",
    "log",
    "--no-graph",
    "-T",
    "id",
  );
  const output = checked(f.run());
  assert.deepEqual(output.cleanup, f.manifest.cleanup);
  assert.deepEqual(output.snapshots, f.manifest.snapshots);
  assert.equal(realpathSync(worker), worker);
  assert.equal(
    jj(
      f.source,
      "--ignore-working-copy",
      "op",
      "log",
      "--no-graph",
      "-T",
      "id",
    ),
    before,
  );
  assert.equal(
    jj(worker, "bookmark", "list", "scratch/worker", "-T", "name"),
    "scratch/worker",
  );
});

test("snapshot commit and change drift are refused", (t) => {
  const f = fixture(t);
  const wrongChange = structuredClone(f.manifest);
  wrongChange.snapshots[0].change = "k".repeat(32);
  refused(f.run(wrongChange), /identity drift/i);
  jj(f.source, "new", "-m", "drift");
  refused(f.run(), /identity drift/i);
});

test("conflicted snapshots are refused", (t) => {
  const f = fixture(t);
  writeFileSync(join(f.source, "file"), "base\n");
  jj(f.source, "commit", "-m", "base");
  const base = jj(f.source, "log", "-G", "-r", "@-", "-T", "commit_id");
  writeFileSync(join(f.source, "file"), "left\n");
  jj(f.source, "commit", "-m", "left");
  const left = jj(f.source, "log", "-G", "-r", "@-", "-T", "commit_id");
  jj(f.source, "new", base);
  writeFileSync(join(f.source, "file"), "right\n");
  jj(f.source, "commit", "-m", "right");
  const right = jj(f.source, "log", "-G", "-r", "@-", "-T", "commit_id");
  jj(f.source, "new", left, right);
  f.manifest.snapshots = [f.pin(f.source)];
  refused(f.run(), /conflicts/i);
});

test("unsnapshotted disk edits are ignored without modifying the operation or pin", (t) => {
  const f = fixture(t);
  const before = jj(
    f.source,
    "--ignore-working-copy",
    "op",
    "log",
    "--no-graph",
    "-T",
    "id",
  );
  writeFileSync(join(f.source, "disk-only"), "not in the pinned commit\n");
  const output = checked(f.run());
  assert.ok(
    output.limitations.some((line) =>
      /snapshot\/check.*immediately before pinning/.test(line),
    ),
  );
  assert.ok(
    output.limitations.some((line) => /Disk drift is not detected/.test(line)),
  );
  assert.deepEqual(f.pin(f.source), f.manifest.snapshots[0]);
  assert.equal(
    jj(
      f.source,
      "--ignore-working-copy",
      "op",
      "log",
      "--no-graph",
      "-T",
      "id",
    ),
    before,
  );
  assert.equal(
    readFileSync(join(f.source, "disk-only"), "utf8"),
    "not in the pinned commit\n",
  );
});

test("all CLI JJ commands are read-only, ignore working copy, disable paging and set cwd", (t) => {
  const f = fixture(t);
  f.cleanup();
  const lookup = spawnSync("/bin/sh", ["-c", "command -v jj"], {
    encoding: "utf8",
  });
  assert.equal(lookup.status, 0, lookup.stderr);
  const actualJJ = lookup.stdout.trim();
  const bin = join(f.root, "bin");
  mkdirSync(bin);
  const log = join(f.root, "calls");
  const wrapper = join(bin, "jj");
  writeFileSync(
    wrapper,
    `#!/bin/sh\nprintf '%s\\n' "$PWD" "$*" >> '${log}'\nexec '${actualJJ}' "$@"\n`,
  );
  chmodSync(wrapper, 0o755);
  checked(
    f.run(f.manifest, { ...process.env, PATH: `${bin}:${process.env.PATH}` }),
  );
  const lines = readFileSync(log, "utf8").trim().split("\n");
  const known = [
    f.source,
    ...f.manifest.cleanup.protectedWorkspaces,
    ...f.manifest.cleanup.workspaces.map((w) => w.path),
  ];
  for (let i = 0; i < lines.length; i += 2) {
    assert.ok(known.includes(lines[i]), lines[i]);
    assert.match(
      lines[i + 1],
      /^--ignore-working-copy --no-pager --color=never --at-operation=@ (root|log|workspace list|bookmark list)( |$)/,
    );
  }
});

test("unavailable or failing jj commands fail closed", (t) => {
  const f = fixture(t);
  refused(
    f.run(f.manifest, { ...process.env, PATH: f.root }),
    /jj root failed.*ENOENT/,
  );
  const wrapper = join(f.root, "jj");
  writeFileSync(wrapper, "#!/bin/sh\nexit 23\n");
  chmodSync(wrapper, 0o755);
  refused(
    f.run(f.manifest, { ...process.env, PATH: f.root }),
    /jj root failed/,
  );
});

test("strict manifest fields, full IDs and unique snapshot roots are required", (t) => {
  const f = fixture(t);
  const cases = [
    [{ ...f.manifest, unexpected: true }, /Unknown field/],
    [{ ...f.manifest, version: 2 }, /version/],
    [{ ...f.manifest, operation: "delete" }, /operation/],
    [{ ...f.manifest, snapshots: [] }, /snapshots/],
    [{ ...f.manifest, snapshots: [null] }, /object/],
    [
      {
        ...f.manifest,
        snapshots: [f.manifest.snapshots[0], f.manifest.snapshots[0]],
      },
      /Duplicate snapshot/,
    ],
    [{ ...f.manifest, cleanup: null }, /must not contain cleanup/],
    [{ ...f.manifest, operation: "cleanup" }, /object/],
    [
      {
        ...f.manifest,
        snapshots: [{ ...f.manifest.snapshots[0], commit: "abc" }],
      },
      /full commit/,
    ],
    [
      {
        ...f.manifest,
        snapshots: [{ ...f.manifest.snapshots[0], change: "abc" }],
      },
      /full change/,
    ],
    [
      {
        ...f.manifest,
        snapshots: [{ ...f.manifest.snapshots[0], extra: true }],
      },
      /Unknown field/,
    ],
    ['{"version":1,"version":1}', /Duplicate field/],
    ['{"version":1,"\\u0076ersion":1}', /Duplicate field/],
    ['{"version":', /JSON/],
  ];
  for (const [manifest, message] of cases) refused(f.run(manifest), message);
});

test("cleanup refuses malformed fields, duplicate targets and nonliteral names", (t) => {
  const f = fixture(t);
  f.cleanup();
  const change = (edit) => {
    const value = structuredClone(f.manifest);
    edit(value.cleanup);
    return value;
  };
  for (const [edit, message] of [
    [
      (c) => {
        c.extra = true;
      },
      /Unknown field/,
    ],
    [
      (c) => {
        c.protectedWorkspaces = [];
      },
      /protectedWorkspaces/,
    ],
    [
      (c) => {
        c.protectedWorkspaces.push(c.protectedWorkspaces[0]);
      },
      /Duplicate protected/,
    ],
    [
      (c) => {
        c.workspaces.push(c.workspaces[0]);
      },
      /Duplicate workspace/,
    ],
    [
      (c) => {
        c.bookmarks.push(c.bookmarks[0]);
      },
      /Duplicate bookmark/,
    ],
    [
      (c) => {
        c.revisions.push(c.revisions[0]);
      },
      /Duplicate revision/,
    ],
    [
      (c) => {
        c.workspaces[0].extra = true;
      },
      /Unknown field/,
    ],
    [
      (c) => {
        c.workspaces[0].name = "wrong";
      },
      /name\/path\/pin mismatch/,
    ],
    [
      (c) => {
        c.revisions = ["@"];
      },
      /full cleanup commit/,
    ],
    [
      (c) => {
        c.revisions = ["f".repeat(40)];
      },
      /failed|one revision/,
    ],
    [
      (c) => {
        c.bookmarks = ["missing"];
      },
      /Missing.*bookmark/,
    ],
  ])
    refused(f.run(change(edit)), message);
  for (const name of [
    "",
    "@",
    "*",
    "glob:foo",
    "all()",
    "a|b",
    "a..b",
    "../foo",
    "-option",
    "foo@origin",
    "a b",
    "/foo",
    ".",
  ]) {
    refused(
      f.run(
        change((c) => {
          c.bookmarks = [name];
        }),
      ),
      /literal name/,
    );
    refused(
      f.run(
        change((c) => {
          c.workspaces[0].name = name;
        }),
      ),
      /literal name/,
    );
  }
  const missingPin = structuredClone(f.manifest);
  missingPin.snapshots = missingPin.snapshots.filter(
    (snapshot) => snapshot.workspace !== f.manifest.cleanup.workspaces[0].path,
  );
  refused(f.run(missingPin), /Missing snapshot/);
});

test("cleanup rejects root, outside, noncanonical and symlink paths", (t) => {
  const f = fixture(t);
  const { worker, cleanupRoot } = f.cleanup();
  const alias = join(cleanupRoot, "alias");
  symlinkSync(worker, alias);
  for (const [path, message] of [
    [cleanupRoot, /strictly inside root/],
    [f.source, /strictly inside root/],
    [`${worker}/../worker`, /canonical/],
    [alias, /symlinks/],
    ["relative", /absolute/],
  ]) {
    const value = structuredClone(f.manifest);
    value.cleanup.workspaces[0].path = path;
    refused(f.run(value), message);
  }
  const value = structuredClone(f.manifest);
  value.cleanup.root = alias;
  refused(f.run(value), /symlinks/);
  value.cleanup.root = cleanupRoot;
  value.snapshots[1].workspace = alias;
  refused(f.run(value), /symlinks/);
});

test("protected workspaces, preserved snapshots and their revision/bookmark targets are refused", (t) => {
  const f = fixture(t);
  const { worker, coordinator } = f.cleanup();
  const sourceCommit = f.pin(f.source).commit;
  const coordinatorCommit = f.pin(coordinator).commit;
  for (const commit of [sourceCommit, coordinatorCommit]) {
    const value = structuredClone(f.manifest);
    value.cleanup.revisions = [commit];
    refused(f.run(value), /Protected revision/);
    jj(worker, "bookmark", "create", "protected-alias", "-r", commit);
    value.cleanup.revisions = [];
    value.cleanup.bookmarks = ["protected-alias"];
    refused(f.run(value), /Protected revision/);
    jj(worker, "bookmark", "delete", "protected-alias");
  }
  const value = structuredClone(f.manifest);
  value.cleanup.protectedWorkspaces.push(worker);
  refused(f.run(value), /protected workspace/);
  value.cleanup.protectedWorkspaces.pop();
  value.cleanup.workspaces = [];
  refused(f.run(value), /Protected revision/);
});

test("persistent task/ bookmarks and their commit targets are protected", (t) => {
  const f = fixture(t);
  const { worker } = f.cleanup();
  jj(worker, "bookmark", "create", "task/persistent", "-r", "@");
  refused(f.run(), /Protected revision/);
  f.manifest.cleanup.workspaces = [];
  f.manifest.cleanup.revisions = [];
  f.manifest.cleanup.bookmarks = ["task/persistent"];
  refused(f.run(), /Persistent task/);
});

test("snapshots and protected roots must be actual roots in one repository", (t) => {
  const f = fixture(t);
  const other = join(f.root, "other");
  jj(f.root, "git", "init", other);
  const value = structuredClone(f.manifest);
  value.snapshots.push(f.pin(other));
  refused(f.run(value), /same repository/);
  const nested = join(f.source, "nested");
  mkdirSync(nested);
  value.snapshots = [{ ...f.manifest.snapshots[0], workspace: nested }];
  refused(f.run(value), /Not a workspace root/);
  f.cleanup();
  f.manifest.cleanup.protectedWorkspaces.push(other);
  refused(f.run(), /same repository|Missing snapshot/);
});

test("unrelated local and remote bookmark targets cannot be abandoned", (t) => {
  const f = fixture(t);
  const { worker } = f.cleanup();
  jj(worker, "bookmark", "create", "main", "-r", "@");
  refused(f.run(), /Protected revision/);
  f.manifest.cleanup.bookmarks.push("main");
  checked(f.run());
  jj(worker, "git", "export");
  checked(f.run());
  jj(worker, "git", "remote", "add", "origin", join(f.source, ".git"));
  jj(worker, "git", "fetch", "--remote", "origin");
  f.manifest.snapshots = f.manifest.snapshots.map((snapshot) =>
    f.pin(snapshot.workspace),
  );
  refused(f.run(), /Protected revision/);
});

test("protected roots require pinned snapshots and coordinator drift is refused", (t) => {
  const f = fixture(t);
  const { coordinator } = f.cleanup();
  const value = structuredClone(f.manifest);
  value.snapshots = value.snapshots.filter(
    (pin) => pin.workspace !== coordinator,
  );
  refused(f.run(value), /Missing snapshot/);
  jj(coordinator, "new", "-m", "coordinator drift");
  refused(f.run(), /identity drift/);
});

test("cleanup may preserve a failed conflicted child under a recoverable bookmark", (t) => {
  const f = fixture(t);
  const { worker } = f.cleanup();
  writeFileSync(join(worker, "file"), "base\n");
  jj(worker, "commit", "-m", "base");
  const base = jj(worker, "log", "-G", "-r", "@-", "-T", "commit_id");
  writeFileSync(join(worker, "file"), "left\n");
  jj(worker, "commit", "-m", "left");
  const left = jj(worker, "log", "-G", "-r", "@-", "-T", "commit_id");
  jj(worker, "new", base);
  writeFileSync(join(worker, "file"), "right\n");
  jj(worker, "commit", "-m", "right");
  const right = jj(worker, "log", "-G", "-r", "@-", "-T", "commit_id");
  jj(worker, "new", left, right);
  f.manifest.snapshots = f.manifest.snapshots.map((pin) =>
    pin.workspace === worker ? f.pin(worker) : pin,
  );
  f.manifest.cleanup.bookmarks = [];
  f.manifest.cleanup.revisions = [];
  jj(worker, "bookmark", "create", "recover/failed", "-r", "@");
  checked(f.run());
  const integration = {
    version: 1,
    operation: "integration",
    snapshots: [f.pin(worker)],
  };
  refused(f.run(integration), /Conflicts/);
  f.manifest.cleanup.revisions = [f.pin(worker).commit];
  refused(f.run(), /Protected revision/);
  f.manifest.cleanup.bookmarks = ["recover/failed"];
  checked(f.run());
  const protectedConflict = structuredClone(f.manifest);
  protectedConflict.cleanup.protectedWorkspaces.push(worker);
  refused(f.run(protectedConflict), /Conflicts/);
  const unselectedConflict = structuredClone(f.manifest);
  unselectedConflict.cleanup.workspaces = [];
  refused(f.run(unselectedConflict), /Conflicts/);
});
