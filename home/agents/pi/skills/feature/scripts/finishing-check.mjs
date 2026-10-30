import { spawnSync } from "node:child_process";
import { readFileSync, realpathSync, statSync } from "node:fs";
import { isAbsolute, join, normalize, resolve } from "node:path";

const commitPattern = /^(?:[0-9a-f]{40}|[0-9a-f]{64}|[0-9a-f]{128})$/;
const changePattern = /^[k-z]{32}$/;
const pinTemplate =
  '\"[\" ++ json(commit_id) ++ "," ++ json(change_id) ++ "," ++ json(conflict) ++ "]\\n"';
const limitations = [
  "Operator approval, ownership, process termination, redundancy and content equivalence still require coordinator verification.",
  "Read-only preflight is not authorization for integration, deletion or abandonment.",
  "--ignore-working-copy ignores unsnapshotted disk edits; the coordinator must snapshot/check each working tree immediately before pinning. Disk drift is not detected.",
  "Run once before each bounded operation; verify command outcomes and final postconditions. Unexpected changes require replanning with fresh verified pins. Concurrent changes are not locked out.",
  "Source/coordinator inclusion in protected roots, indirect revision effects and recoverability require coordinator verification.",
];

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

function object(value, required, optional = []) {
  requireValue(
    value !== null && typeof value === "object" && !Array.isArray(value),
    "Expected object",
  );
  for (const key of required)
    requireValue(Object.hasOwn(value, key), `Missing field: ${key}`);
  for (const key of Object.keys(value)) {
    requireValue(
      required.includes(key) || optional.includes(key),
      `Unknown field: ${key}`,
    );
  }
}

function array(value, label, nonempty = false) {
  requireValue(
    Array.isArray(value) && (!nonempty || value.length > 0),
    `Invalid ${label} array`,
  );
}

function unique(values, label) {
  requireValue(new Set(values).size === values.length, `Duplicate ${label}`);
}

function directory(path) {
  requireValue(
    typeof path === "string" && isAbsolute(path) && normalize(path) === path,
    "Path must be absolute and canonical",
  );
  requireValue(
    realpathSync(path) === path && statSync(path).isDirectory(),
    `Path must be a canonical directory without symlinks: ${path}`,
  );
  return path;
}

function parseManifest(text) {
  const value = JSON.parse(text);
  // JSON.parse discards duplicate object keys.
  const tokens = /"(?:[^"\\]|\\.)*"|[{}\[\]:,]/g;
  const stack = [];
  for (const match of text.matchAll(tokens)) {
    const token = match[0];
    if (token === "{") stack.push(new Set());
    else if (token === "[") stack.push(null);
    else if (token === "}" || token === "]") stack.pop();
    else if (
      token.startsWith('"') &&
      text
        .slice(match.index + token.length)
        .trimStart()
        .startsWith(":")
    ) {
      const key = JSON.parse(token);
      requireValue(!stack.at(-1).has(key), `Duplicate field: ${key}`);
      stack.at(-1).add(key);
    }
  }
  return value;
}

function jj(cwd, ...args) {
  const result = spawnSync(
    "jj",
    [
      "--ignore-working-copy",
      "--no-pager",
      "--color=never",
      "--at-operation=@",
      ...args,
    ],
    {
      cwd,
      encoding: "utf8",
      timeout: 15000,
      maxBuffer: 8 * 1024 * 1024,
    },
  );
  requireValue(
    !result.error && result.status === 0,
    `jj ${args[0]} failed in ${cwd}: ${result.error?.message || result.stderr.trim()}`,
  );
  return result.stdout.trim();
}

function rows(cwd, ...args) {
  const output = jj(cwd, ...args);
  return output ? output.split("\n").map((line) => JSON.parse(line)) : [];
}

function pin(cwd, revision = "@", allowConflicts = false) {
  const result = rows(
    cwd,
    "log",
    "--no-graph",
    "-r",
    revision,
    "-T",
    pinTemplate,
  );
  requireValue(result.length === 1, `Expected one revision in ${cwd}`);
  const [commit, change, conflict] = result[0];
  requireValue(
    commitPattern.test(commit) &&
      changePattern.test(change) &&
      typeof conflict === "boolean",
    "Invalid jj snapshot output",
  );
  requireValue(
    allowConflicts || !conflict,
    `Conflicts in revision ${commit} (${cwd})`,
  );
  return { workspace: cwd, commit, change };
}

function repository(workspace) {
  requireValue(
    jj(workspace, "root") === workspace,
    `Not a workspace root: ${workspace}`,
  );
  // Linked workspaces store a repository-directory pointer in .jj/repo.
  const path = join(workspace, ".jj", "repo");
  const target = statSync(path).isDirectory()
    ? path
    : resolve(workspace, ".jj", readFileSync(path, "utf8").trim());
  requireValue(
    statSync(target).isDirectory(),
    `Invalid repository directory: ${workspace}`,
  );
  return realpathSync(target);
}

function literalName(value) {
  requireValue(
    typeof value === "string" &&
      /^[A-Za-z0-9][A-Za-z0-9._-]*(?:\/[A-Za-z0-9][A-Za-z0-9._-]*)*$/.test(
        value,
      ) &&
      !value.includes(".."),
    "Expected a literal name without special, wildcard or revset syntax",
  );
}

function inside(path, root) {
  return path.startsWith(root.endsWith("/") ? root : `${root}/`);
}

function checkCleanup(manifest, repo) {
  const cleanup = manifest.cleanup;
  object(cleanup, [
    "root",
    "protectedWorkspaces",
    "workspaces",
    "bookmarks",
    "revisions",
  ]);
  directory(cleanup.root);
  array(cleanup.protectedWorkspaces, "protectedWorkspaces", true);
  array(cleanup.workspaces, "workspaces");
  array(cleanup.bookmarks, "bookmarks");
  array(cleanup.revisions, "revisions");
  unique(cleanup.protectedWorkspaces, "protected workspace");
  unique(
    cleanup.workspaces.map((workspace) => workspace?.name),
    "workspace name",
  );
  unique(
    cleanup.workspaces.map((workspace) => workspace?.path),
    "workspace path",
  );
  unique(cleanup.bookmarks, "bookmark");
  unique(cleanup.revisions, "revision");

  const cwd = manifest.snapshots[0].workspace;
  const workspaceRows = rows(
    cwd,
    "workspace",
    "list",
    "-T",
    '\"[\" ++ json(name) ++ "," ++ json(root) ++ "," ++ json(target.commit_id()) ++ "]\\n"',
  );
  const selected = new Set(
    cleanup.workspaces.map((workspace) => workspace.path),
  );
  const protectedCommits = new Set();
  for (const path of cleanup.protectedWorkspaces) {
    directory(path);
    requireValue(
      repository(path) === repo,
      "Protected workspaces must share the same repository",
    );
    requireValue(
      manifest.snapshots.some((snapshot) => snapshot.workspace === path),
      `Missing snapshot for protected workspace: ${path}`,
    );
    const actual = pin(path);
    requireValue(
      workspaceRows.some(
        ([, root, commit]) => root === path && commit === actual.commit,
      ),
      `Protected workspace not registered at its current pin: ${path}`,
    );
    protectedCommits.add(actual.commit);
  }
  for (const snapshot of manifest.snapshots) {
    if (!selected.has(snapshot.workspace))
      protectedCommits.add(snapshot.commit);
  }
  for (const [, path, commit] of workspaceRows) {
    if (!selected.has(path)) protectedCommits.add(commit);
  }

  for (const workspace of cleanup.workspaces) {
    object(workspace, ["name", "path"]);
    literalName(workspace.name);
    directory(workspace.path);
    requireValue(
      inside(workspace.path, cleanup.root),
      "Cleanup path must be strictly inside root",
    );
    requireValue(
      !cleanup.protectedWorkspaces.some(
        (path) =>
          workspace.path === path ||
          inside(path, workspace.path) ||
          inside(workspace.path, path),
      ),
      "Cleanup path overlaps a protected workspace",
    );
    requireValue(
      !cleanup.workspaces.some(
        (other) => other !== workspace && inside(other.path, workspace.path),
      ),
      "Overlapping cleanup workspaces",
    );
    const snapshot = manifest.snapshots.find(
      (entry) => entry.workspace === workspace.path,
    );
    requireValue(
      snapshot,
      `Missing snapshot for cleanup workspace: ${workspace.path}`,
    );
    requireValue(
      repository(workspace.path) === repo,
      "Cleanup workspaces must share the same repository",
    );
    requireValue(
      workspaceRows.some(
        ([name, path, commit]) =>
          name === workspace.name &&
          path === workspace.path &&
          commit === snapshot.commit,
      ),
      `Workspace name/path/pin mismatch: ${workspace.name}`,
    );
  }

  const bookmarks = rows(
    cwd,
    "bookmark",
    "list",
    "--all-remotes",
    "-T",
    '\"[\" ++ json(name) ++ "," ++ json(remote) ++ "," ++ json(conflict) ++ "," ++ json(added_targets.map(|c| c.commit_id())) ++ "," ++ json(removed_targets.map(|c| c.commit_id())) ++ "]\\n"',
  );
  for (const [name, remote, , added, removed] of bookmarks) {
    if (
      (remote !== null && remote !== "git") ||
      name.startsWith("task/") ||
      !cleanup.bookmarks.includes(name)
    ) {
      for (const commit of [...added, ...removed]) protectedCommits.add(commit);
    }
  }
  const unprotected = (commit) =>
    requireValue(
      !protectedCommits.has(commit) && !/^0+$/.test(commit),
      `Protected revision target: ${commit}`,
    );
  for (const name of cleanup.bookmarks) {
    literalName(name);
    requireValue(
      !name.startsWith("task/"),
      "Persistent task/ bookmarks are protected",
    );
    const bookmark = bookmarks.find(
      ([candidate, remote]) => candidate === name && remote === null,
    );
    requireValue(
      bookmark &&
        bookmark[2] === false &&
        bookmark[3].length === 1 &&
        bookmark[4].length === 0,
      `Missing or conflicted local bookmark: ${name}`,
    );
    unprotected(bookmark[3][0]);
  }
  for (const revision of cleanup.revisions) {
    requireValue(
      typeof revision === "string" && commitPattern.test(revision),
      "Expected full cleanup commit ID",
    );
    unprotected(revision);
    requireValue(
      pin(cwd, revision, true).commit === revision,
      `Revision does not resolve to exact commit: ${revision}`,
    );
  }
  return cleanup;
}

function check(manifest) {
  object(manifest, ["version", "operation", "snapshots"], ["cleanup"]);
  requireValue(manifest.version === 1, "Unsupported version");
  requireValue(
    ["integration", "cleanup"].includes(manifest.operation),
    "Invalid operation",
  );
  array(manifest.snapshots, "snapshots", true);
  unique(
    manifest.snapshots.map((snapshot) => snapshot?.workspace),
    "snapshot workspace",
  );
  let repo;
  for (const snapshot of manifest.snapshots) {
    object(snapshot, ["workspace", "commit", "change"]);
    directory(snapshot.workspace);
    requireValue(
      typeof snapshot.commit === "string" &&
        commitPattern.test(snapshot.commit),
      "Expected full commit ID",
    );
    requireValue(
      typeof snapshot.change === "string" &&
        changePattern.test(snapshot.change),
      "Expected full change ID",
    );
    const identity = repository(snapshot.workspace);
    repo ??= identity;
    requireValue(
      identity === repo,
      "Workspaces must share the same repository",
    );
    const selectedCleanup =
      manifest.operation === "cleanup" &&
      Array.isArray(manifest.cleanup?.workspaces) &&
      manifest.cleanup.workspaces.some(
        (entry) => entry?.path === snapshot.workspace,
      ) &&
      Array.isArray(manifest.cleanup?.protectedWorkspaces) &&
      !manifest.cleanup.protectedWorkspaces.includes(snapshot.workspace);
    const actual = pin(snapshot.workspace, "@", selectedCleanup);
    requireValue(
      actual.commit === snapshot.commit && actual.change === snapshot.change,
      `Snapshot identity drift: ${snapshot.workspace}`,
    );
  }
  requireValue(
    manifest.operation !== "integration" || !Object.hasOwn(manifest, "cleanup"),
    "Integration must not contain cleanup",
  );
  const cleanup =
    manifest.operation === "cleanup" ? checkCleanup(manifest, repo) : undefined;
  return {
    status: "checked",
    operation: manifest.operation,
    snapshots: manifest.snapshots,
    ...(cleanup ? { cleanup } : {}),
    limitations,
  };
}

try {
  requireValue(
    process.argv.length === 3,
    "Usage: node finishing-check.mjs MANIFEST.json",
  );
  const manifest = parseManifest(readFileSync(process.argv[2], "utf8"));
  console.log(JSON.stringify(check(manifest)));
} catch (error) {
  console.error(`finishing-check: ${error.message}`);
  process.exitCode = 1;
}
