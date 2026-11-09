import assert from "node:assert/strict";
import test from "node:test";
import { registerSessionName } from "./session-name/name.mjs";

const Type = {
  Object: (properties) => ({ type: "object", properties }),
  String: (options) => ({ type: "string", ...options }),
};

function harness(initial = "feature: implementing") {
  let name = initial;
  const writes = [];
  let tool;
  registerSessionName(
    {
      registerTool(value) {
        tool = value;
      },
      getSessionName: () => name,
      setSessionName(value) {
        writes.push(value);
        name = value;
      },
    },
    Type,
  );
  return { tool, writes, name: () => name };
}

test("renames the current Pi conversation and verifies the result", async () => {
  const h = harness();
  assert.equal(h.tool.name, "set_session_name");
  const result = await h.tool.execute("call", { name: "feature: review" });
  assert.equal(h.name(), "feature: review");
  assert.deepEqual(h.writes, ["feature: review"]);
  assert.deepEqual(result.details, { name: "feature: review", changed: true });
});

test("skips unchanged names and reads the live session on each call", async () => {
  const h = harness("feature: review");
  assert.equal(
    (await h.tool.execute("a", { name: "feature: review" })).details.changed,
    false,
  );
  await h.tool.execute("b", { name: "feature: blocked" });
  await h.tool.execute("c", { name: "feature: review" });
  assert.deepEqual(h.writes, ["feature: blocked", "feature: review"]);
});

test("rejects empty, multiline, control and oversized names before mutation", async () => {
  const h = harness();
  for (const name of [
    "",
    "  ",
    "feature\nreview",
    "feature\rreview",
    "feature\u001b",
    "a".repeat(121),
    null,
  ]) {
    await assert.rejects(() => h.tool.execute("call", { name }), /name/i);
  }
  assert.deepEqual(h.writes, []);
});

test("reports failed native renames rather than claiming success", async () => {
  let tool;
  registerSessionName(
    {
      registerTool(value) {
        tool = value;
      },
      getSessionName: () => "old",
      setSessionName() {},
    },
    Type,
  );
  await assert.rejects(() => tool.execute("call", { name: "new" }), /verify/i);
});
