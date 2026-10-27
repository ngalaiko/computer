import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

test("subagents run in the background with live fleet visibility", () => {
  const config = JSON.parse(read("./subagents/config.json"));
  assert.equal(config.asyncByDefault, true);
  assert.equal(config.forceTopLevelAsync, true);
  assert.equal(config.fleetView, true);
  assert.equal(config.maxActiveAsyncRunsPerSession, 2);
  assert.equal(config.globalConcurrencyLimit, 2);
  assert.equal(config.maxSubagentDepth, 1);
  assert.equal(config.worktree, false);
  assert.equal(config.defaultSubagentContext, "fresh");
  assert.equal(config.autoResume, false);
  assert.equal(config.asyncWidget, false);
  assert.equal(config.inlineToolDisplay, "summary");
});

test("custom agents pin models, tools, extensions, and fresh context", () => {
  for (const [role, model, thinking, tools] of [
    ["worker", "openai-codex/gpt-6.1-sol", "medium", "read, bash, edit, write"],
    [
      "small-worker",
      "openai-codex/gpt-6.1-terra",
      "medium",
      "read, bash, edit, write",
    ],
    ["reviewer", "claude-code-cli/opus", "high", "read, grep, find, ls"],
  ]) {
    const definition = read(`./subagents/${role}.md`);
    const [, frontmatter] = definition.split("---");
    const fields = Object.fromEntries(
      frontmatter
        .trim()
        .split("\n")
        .map((line) => {
          const colon = line.indexOf(":");
          return [line.slice(0, colon), line.slice(colon + 1).trim()];
        }),
    );
    assert.equal(fields.name, role);
    assert.equal(fields.model, model);
    assert.equal(fields.thinking, thinking);
    assert.equal(fields.tools, tools);
    assert.equal(fields.async, "true");
    assert.equal(fields.advertise, "true");
    assert.equal(fields.defaultContext, "fresh");
    if (role !== "reviewer") assert.equal(fields.acceptance, "attested");
    assert.equal(fields.inheritProjectContext, "true");
    assert.equal(fields.inheritGlobalContext, "true");
    assert.equal(fields.inheritSkills, "false");
    assert.equal(fields.systemPromptMode, "append");
    assert.equal(
      fields.acceptanceRole,
      role === "reviewer" ? "read-only" : "writer",
    );
    assert.equal(
      fields.extensions,
      role === "reviewer"
        ? "../extensions/command-guards.ts, ../npm/node_modules/claude-code-pi"
        : "../extensions/command-guards.ts",
    );
    assert.match(definition, /Work directly without delegating/);
  }
});

test("Home Manager deploys upstream subagents instead of the custom runner", () => {
  const module = read("../pi.nix");
  assert.match(module, /npm:pi-subagents@0\.82\.1/);
  assert.match(module, /disableBuiltins = true/);
  assert.match(module, /\.pi\/agent\/extensions\/subagent\/config\.json/);
  for (const role of ["worker", "small-worker", "reviewer"]) {
    assert.ok(module.includes(`".pi/agent/agents/${role}.md"`));
  }
  assert.doesNotMatch(module, /delegate\.ts|model-routing\.ts/);
});

test("delegation instructions are Pi-only and scoped to parent sessions", () => {
  assert.doesNotMatch(read("../AGENTS.md"), /<delegation>/);
  const instructions = read("./AGENTS.md");
  assert.match(instructions, /Parent Pi sessions only/);
  assert.match(instructions, /git\.colocate=false workspace add/);
  assert.match(read("../pi.nix"), /builtins\.readFile \.\/pi\/AGENTS\.md/);
});

test("settings activation replaces stale routing without losing unrelated settings", (t) => {
  const directory = mkdtempSync(join(tmpdir(), "pi-settings-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const target = join(directory, "settings.json");
  const defaults = join(directory, "defaults.json");
  writeFileSync(
    target,
    JSON.stringify({
      editorPaddingX: 3,
      subagents: {
        defaultModel: "tiered/worker",
        defaultSubagentOnlyExtensions: ["model-routing.ts"],
      },
    }),
  );
  const managed = {
    packages: ["npm:pi-subagents@0.82.1"],
    subagents: { disableBuiltins: true },
  };
  writeFileSync(defaults, JSON.stringify(managed));
  execFileSync("python3", [
    new URL("./settings.py", import.meta.url).pathname,
    target,
    defaults,
  ]);
  assert.deepEqual(JSON.parse(readFileSync(target, "utf8")), {
    editorPaddingX: 3,
    ...managed,
  });
});

test(
  "installed upstream resolves the deployed agent launch contracts",
  {
    skip: !process.env.PI_SDK_ENTRY || !process.env.PI_SUBAGENTS_DIR,
  },
  async (t) => {
    const directory = realpathSync(
      mkdtempSync(join(tmpdir(), "pi-subagents-")),
    );
    t.after(() => rmSync(directory, { recursive: true, force: true }));
    const agentDir = join(directory, "agent");
    const cwd = join(directory, "repo");
    for (const path of [
      cwd,
      join(agentDir, "agents"),
      join(agentDir, "extensions", "subagent"),
      join(agentDir, "npm", "node_modules"),
    ])
      mkdirSync(path, { recursive: true });
    writeFileSync(
      join(agentDir, "settings.json"),
      JSON.stringify({
        subagents: { disableBuiltins: true, defaultExtensions: [] },
      }),
    );
    writeFileSync(
      join(agentDir, "extensions", "subagent", "config.json"),
      read("./subagents/config.json"),
    );
    const profiles = [
      [
        "worker",
        "openai-codex/gpt-6.1-sol",
        "medium",
        ["read", "bash", "edit", "write"],
      ],
      [
        "small-worker",
        "openai-codex/gpt-6.1-terra",
        "medium",
        ["read", "bash", "edit", "write"],
      ],
      [
        "reviewer",
        "claude-code-cli/opus",
        "high",
        ["read", "grep", "find", "ls"],
      ],
    ];
    for (const [role] of profiles)
      symlinkSync(
        fileURLToPath(new URL(`./subagents/${role}.md`, import.meta.url)),
        join(agentDir, "agents", `${role}.md`),
      );
    symlinkSync(
      fileURLToPath(new URL("./command-guards.ts", import.meta.url)),
      join(agentDir, "extensions", "command-guards.ts"),
    );
    symlinkSync(
      join(dirname(process.env.PI_SUBAGENTS_DIR), "claude-code-pi"),
      join(agentDir, "npm", "node_modules", "claude-code-pi"),
    );
    const previous = process.env.PI_CODING_AGENT_DIR;
    process.env.PI_CODING_AGENT_DIR = agentDir;
    t.after(() => {
      if (previous === undefined) delete process.env.PI_CODING_AGENT_DIR;
      else process.env.PI_CODING_AGENT_DIR = previous;
    });
    const sdk = process.env.PI_SDK_ENTRY;
    const sdkRoot = dirname(dirname(sdk));
    const require = createRequire(sdk);
    const { createJiti } = require("jiti");
    const alias = Object.fromEntries(
      ["pi-ai", "pi-agent-core", "pi-tui"].map((name) => [
        `@earendil-works/${name}`,
        join(
          sdkRoot,
          "node_modules",
          "@earendil-works",
          name,
          "dist",
          "index.js",
        ),
      ]),
    );
    alias["@earendil-works/pi-coding-agent"] = sdk;
    const jiti = createJiti(import.meta.url, { alias });
    const { resolveSubagentLaunchContract } = await jiti.import(
      join(process.env.PI_SUBAGENTS_DIR, "bundle", "preflight.js"),
    );
    const availableModels = profiles.map(([, model]) => {
      const [provider, id] = model.split("/");
      return { provider, id, reasoning: true };
    });
    for (const [agent, model, thinking, tools] of profiles) {
      const result = await resolveSubagentLaunchContract({
        agent,
        task: "Check the launch contract.",
        cwd,
        agentScope: "user",
        availableModels,
        intercomBridge: { mode: "off" },
      });
      assert.equal(result.ok, true, JSON.stringify(result));
      const contract = result.contract;
      assert.equal(contract.model, `${model}:${thinking}`);
      assert.equal(contract.context, "fresh");
      assert.equal(contract.tools.disableAmbientExtensions, true);
      assert.equal(contract.tools.fanoutAuthorized, false);
      assert.deepEqual(contract.tools.effectiveAllowlist, tools);
      assert.deepEqual(contract.tools.configuredExtensions, [
        join(agentDir, "extensions", "command-guards.ts"),
        ...(agent === "reviewer"
          ? [join(agentDir, "npm", "node_modules", "claude-code-pi")]
          : []),
      ]);
    }
  },
);
