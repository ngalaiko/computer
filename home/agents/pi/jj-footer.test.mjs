import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import { homedir } from "node:os";
import test from "node:test";
import { pathToFileURL } from "node:url";

if (process.env.PI_TEST_TUI) {
  registerHooks({
    resolve(specifier, context, next) {
      return next(
        specifier === "@earendil-works/pi-tui"
          ? pathToFileURL(process.env.PI_TEST_TUI).href
          : specifier,
        context,
      );
    },
  });
}
const { default: footerExtension } = await import("./jj-footer.ts");
const { visibleWidth } = await import("@earendil-works/pi-tui");

async function setup(t, responses, mode = "tui") {
  const handlers = new Map();
  const calls = [];
  let footer;
  const ctx = {
    mode,
    cwd: `${homedir()}/project`,
    model: { provider: "openai-codex", id: "gpt-test", contextWindow: 500000 },
    getContextUsage: () => ({
      tokens: 50000,
      contextWindow: 500000,
      percent: 10,
    }),
    ui: {
      setFooter(factory) {
        footer = factory(
          { requestRender() {} },
          { fg: (_color, text) => text },
          {
            getExtensionStatuses: () => new Map(),
          },
        );
      },
    },
  };
  footerExtension({
    on: (event, handler) => handlers.set(event, handler),
    getThinkingLevel: () => "medium",
    exec: async (command, args, options) => {
      calls.push({ command, args, options });
      const response = responses.shift();
      if (response instanceof Error) throw response;
      return response ?? { code: 1, stdout: "" };
    },
  });
  t.after(() => handlers.get("session_shutdown")());
  handlers.get("session_start")({}, ctx);
  await new Promise((resolve) => setImmediate(resolve));
  return { footer, calls, ctx, handlers };
}

const ok = (stdout) => ({ code: 0, stdout });

test("matches Fish bookmark, ids and dirty state; retains model and context", async (t) => {
  const { footer, calls } = await setup(t, [ok("main\nabc1 def2 dirty")]);
  const lines = footer.render(100);
  assert.equal(lines.length, 1);
  assert.match(lines[0], /^~\/project \[main abc1 def2 dirty\]/);
  assert.match(lines[0], /\(openai-codex\) gpt-test · medium/);
  assert.match(lines[0], /ctx 10\.0%\/500k$/);
  assert.doesNotMatch(lines.join("\n"), /sub|\$|detached/);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].command, "jj");
  assert.equal(calls[0].options.cwd, `${homedir()}/project`);
  assert.ok(calls[0].args.includes("--ignore-working-copy"));
});

test("preserves jj bookmark and shortest-id highlighting on one line", async (t) => {
  const { footer, calls } = await setup(t, [
    ok(
      "\u001b[35mmain\u001b[0m\n\u001b[1;35ma\u001b[0mbc1 \u001b[1;34md\u001b[0mef2 dirty",
    ),
  ]);
  const lines = footer.render(100);
  assert.equal(lines.length, 1);
  assert.ok(lines[0].includes("\u001b[35mmain\u001b[0m"));
  assert.ok(lines[0].includes("\u001b[1;35ma\u001b[0mbc1"));
  assert.ok(lines[0].includes("\u001b[1;34md\u001b[0mef2"));
  assert.equal(calls[0].args[calls[0].args.indexOf("--color") + 1], "always");
  assert.ok(visibleWidth(lines[0]) <= 100);
});

test("shows nearest bookmarks and intervening commit count", async (t) => {
  const { footer } = await setup(t, [
    ok("\nabc1 def2 clean"),
    ok("~main\n"),
    ok("xxx"),
  ]);
  assert.ok(
    footer.render(160)[0].startsWith("~/project [~main +3 abc1 def2 clean]"),
  );
});

test("omits zero distance and handles repositories without bookmarks", async (t) => {
  for (const [closest, expected] of [
    ["~main\n", "~main "],
    ["", ""],
  ]) {
    const { footer } = await setup(t, [
      ok("\nabc1 def2 clean"),
      ok(closest),
      ok(""),
    ]);
    assert.ok(
      footer
        .render(160)[0]
        .startsWith(`~/project [${expected}abc1 def2 clean]`),
    );
  }
});

test("missing jj or a non-jj directory leaves just the path", async (t) => {
  for (const response of [new Error("ENOENT"), { code: 1, stdout: "" }]) {
    const { footer } = await setup(t, [response]);
    assert.match(footer.render(100)[0], /^~\/project\s+\(openai-codex\)/);
  }
});

test("unknown context is not reported as zero; model updates are live", async (t) => {
  const { footer, ctx } = await setup(t, []);
  ctx.getContextUsage = () => undefined;
  ctx.model.id = "new-model";
  assert.match(footer.render(100)[0], /new-model/);
  assert.match(footer.render(100)[0], /ctx \?\/500k$/);
});

test("fits narrow terminals and wide model names", async (t) => {
  const { footer, ctx } = await setup(t, [ok("main\nabc1 def2 dirty")]);
  ctx.model.id = "模型".repeat(80);
  for (let width = 1; width <= 120; width++) {
    const lines = footer.render(width);
    assert.equal(lines.length, 1);
    for (const line of lines) assert.ok(visibleWidth(line) <= width);
  }
});

test("refreshes jj after an agent run", async (t) => {
  const { footer, handlers } = await setup(t, [
    ok("main\nabc1 def2 dirty"),
    ok("next\nabc2 def3 clean"),
  ]);
  await handlers.get("agent_end")();
  assert.ok(
    footer.render(160)[0].startsWith("~/project [next abc2 def3 clean]"),
  );
});

test("does not start processes outside the TUI", async (t) => {
  const { footer, calls } = await setup(t, [], "print");
  assert.equal(footer, undefined);
  assert.equal(calls.length, 0);
});
