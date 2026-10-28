import assert from "node:assert/strict";
import { homedir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import skillPolicy from "./skill-policy.ts";

function apply(names, cwd = homedir(), explicit = [], scope = "user") {
  let handler;
  skillPolicy({
    on(event, fn) {
      assert.equal(event, "before_agent_start");
      handler = fn;
    },
  });
  const skills = names.map((name) => ({
    name,
    description: name,
    filePath: `/skills/${name}/SKILL.md`,
    sourceInfo: { scope },
    disableModelInvocation: explicit.includes(name),
  }));
  const event = { systemPromptOptions: { skills } };
  handler(event, { cwd });
  assert.deepEqual(
    skills.map((s) => s.disableModelInvocation),
    names.map((n) => explicit.includes(n)),
  );
  assert.deepEqual(
    event.systemPromptOptions.skills.map((s) => s.name),
    names,
  );
  return event.systemPromptOptions.skills
    .filter((s) => !s.disableModelInvocation)
    .map((s) => s.name);
}

test("advertises the global coding skills", () => {
  const names = [
    "agent-browser",
    "diagnosing-bugs",
    "tdd",
    "code-review",
    "codebase-design",
    "writing-for-agents",
  ];
  assert.deepEqual(apply(names), names);
});

test("keeps document and deliberate workflows explicit-only", () => {
  assert.deepEqual(
    apply([
      "docx",
      "xlsx",
      "pptx",
      "pdf",
      "grilling",
      "council-mode",
      "prototype",
      "wizard",
      "domain-modeling",
      "research",
      "handoff",
      "lint",
      "pr",
      "grill-me",
      "grill-with-docs",
      "unknown-skill",
    ]),
    [],
  );
});

test("keeps subagent guidance discoverable", () => {
  assert.deepEqual(apply(["pi-subagents"]), ["pi-subagents"]);
});

test("preserves an upstream explicit-only flag", () => {
  assert.deepEqual(apply(["tdd"], homedir(), ["tdd"]), []);
});

test("preserves project and command-line skill discovery", () => {
  for (const scope of ["project", "temporary"]) {
    assert.deepEqual(apply(["local-skill"], homedir(), [], scope), [
      "local-skill",
    ]);
    assert.deepEqual(
      apply(["local-skill"], homedir(), ["local-skill"], scope),
      [],
    );
  }
});

test("advertises Encore and Rex regardless of directory", () => {
  const names = ["encore-service", "rex"];
  for (const cwd of [homedir(), join(homedir(), "Developer/other")]) {
    assert.deepEqual(apply(names, cwd), names);
  }
});

test("advertises feature tabs globally, respecting explicit-only", () => {
  for (const cwd of [homedir(), join(homedir(), "Developer/other")]) {
    assert.deepEqual(apply(["feature-tabs"], cwd), ["feature-tabs"]);
    assert.deepEqual(apply(["feature-tabs"], cwd, ["feature-tabs"]), []);
  }
});

test("advertises Hunk reviews globally, respecting explicit-only", () => {
  for (const cwd of [homedir(), join(homedir(), "Developer/other")]) {
    assert.deepEqual(apply(["hunk-review"], cwd), ["hunk-review"]);
    assert.deepEqual(apply(["hunk-review"], cwd, ["hunk-review"]), []);
  }
});
