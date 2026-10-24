import assert from "node:assert/strict";
import test from "node:test";
import commandGuards from "./command-guards.ts";

let guard;
commandGuards({
  on(event, handler) {
    assert.equal(event, "tool_call");
    guard = handler;
  },
});

for (const command of [
  "git status",
  "git push",
  "cd repo && git diff",
  "true; git status",
  "true\ngit status",
  "echo $(git status)",
  "echo `git status`",
  "jj git push",
  "jj --repository repo git push --all",
  "jj git --remote origin push",
  "jj git fetch && jj git push",
]) {
  test(`blocks ${JSON.stringify(command)}`, async () => {
    const result = await guard({ toolName: "bash", input: { command } });
    assert.equal(result?.block, true);
    assert.ok(result.reason);
  });
}

for (const command of [
  "jj status",
  "jj git fetch",
  "jj git import",
  "jj log",
  "echo git",
  'rg "never use git" AGENTS.md',
  "nix flake check",
]) {
  test(`allows ${JSON.stringify(command)}`, async () => {
    assert.equal(
      await guard({ toolName: "bash", input: { command } }),
      undefined,
    );
  });
}

test("ignores other tools", async () => {
  assert.equal(
    await guard({ toolName: "read", input: { path: "git" } }),
    undefined,
  );
});
