import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import test from "node:test";

const directory = new URL("./skills/feature/", import.meta.url);
const read = (name) => readFileSync(new URL(name, directory), "utf8");

test("feature references have valid local files and heading anchors", () => {
  for (const name of readdirSync(directory).filter((name) =>
    name.endsWith(".md"),
  )) {
    for (const [, file, anchor] of read(name).matchAll(
      /\]\(([^)#]*\.md)?(?:#([^)]*))?\)/g,
    )) {
      const target = read(file || name);
      if (!anchor) continue;
      const headings = [...target.matchAll(/^#+ (.+)$/gm)].map(([, heading]) =>
        heading
          .toLowerCase()
          .replace(/[^\w\s-]/g, "")
          .replace(/\s+/g, "-"),
      );
      assert.ok(headings.includes(anchor), `${name}: ${file}#${anchor}`);
    }
  }
});

test("finishing gates have one authoritative phase reference", () => {
  const review = read("oyo-review.md");
  const finishing = read("finishing.md");
  for (const heading of [
    "Revision safety",
    "Integration",
    "Cleanup",
    "History refactoring",
    "Local-only integration and cleanup",
  ]) {
    assert.ok(finishing.includes(`## ${heading}\n`), heading);
    assert.doesNotMatch(review, new RegExp(`^#{2,3} ${heading}$`, "m"));
  }
  assert.match(
    read("SKILL.md"),
    /\[Finishing\]\(finishing\.md\) before integration or cleanup/,
  );
  assert.match(review, /finishing\.md#revision-safety/);
  assert.match(read("github-pr.md"), /\[Finishing\]\(finishing\.md\)/);
});

test("smaller-model finishing is bounded and independently verified", () => {
  const finishing = read("finishing.md");
  for (const contract of [
    "## Executor contract",
    "## Scripted preflight",
    "## Trial evidence",
    "small-worker",
    "worker",
    "conflict-free",
    "before each mutating command",
    "at most one model-tier escalation",
    "parent inspects actual history/tree",
    "parent corrections",
    "elapsed time",
    "retries/escalation",
    "total token/cost",
    "not token price alone",
  ]) {
    assert.ok(finishing.includes(contract), contract);
  }
  assert.match(
    finishing,
    /approval, ownership, recoverability and process termination before dispatch/,
  );
  assert.match(finishing, /Never regenerate expected pins/);
  assert.match(finishing, /scripts\/finishing-check\.mjs/);
  assert.match(
    finishing,
    /workspace-forget plus exact-directory removal.*one explicitly approved shell command unit joined with `&&`/,
  );
  assert.match(
    finishing,
    /forgotten workspace cannot pass workspace-registration preflight again/,
  );
  assert.doesNotMatch(finishing, /^name:|^description:/m);
});

test("finishing checks post-mutation conflicts and returns resolution to implementation", () => {
  const finishing = read("finishing.md");
  assert.match(finishing, /After each mutation.*conflicts\(\).*exit status/is);
  assert.match(
    finishing,
    /separate.*worker.*implementation brief.*conflict resolution/is,
  );
});

test("local history rewriting precedes source integration; trials survive teardown", () => {
  const finishing = read("finishing.md");
  assert.match(
    finishing,
    /Local-only history rewriting.*task workspace.*before.*integration/i,
  );
  assert.match(finishing, /finishing-trials\/<task-key>\.jsonl/);
  assert.match(finishing, /Trial records survive task cleanup/i);
  assert.match(
    finishing,
    /Commit nonempty consolidated work.*empty.*undescribed.*@/i,
  );
  assert.match(finishing, /persistent task bookmark.*described.*revision/i);
});

test("writers start from an explicitly pinned task revision", () => {
  for (const name of ["SKILL.md", "oyo-review.md", "github-pr.md"]) {
    assert.match(read(name), /writer_base/);
    assert.doesNotMatch(read(name), /workspace add[^\n]*-r @/);
  }
  const readme = readFileSync(new URL("./README.md", import.meta.url), "utf8");
  assert.match(readme, /workspace add[^\n]*-r "\$writer_base"/);
});

test("local-only and history finishing retain approval and recovery gates", () => {
  const finishing = read("finishing.md");
  const local = finishing
    .split("## Local-only integration and cleanup\n")[1]
    .split("## Integration\n")[0];
  for (const gate of [
    "explicit approval of the exact reviewed changes and destination",
    "Verify the recorded source identity",
    "Only this approved local-only integration may change default/source",
    "empty and undescribed",
    "explicit user completion",
    "coordinator Pi/tab must exit",
    "Never delete a live cwd",
  ])
    assert.ok(local.includes(gate), gate);
  const history = finishing
    .split("## History refactoring\n")[1]
    .split("## Cleanup\n")[0];
  for (const gate of [
    "Rewriting published history requires explicit approval",
    "conflict-free",
    "complete base-to-tip diff match the approved result",
    "renewed integration approval",
  ])
    assert.ok(history.includes(gate), gate);
});
