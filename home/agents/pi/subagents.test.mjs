import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import test from "node:test";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const json = (path) => JSON.parse(read(path));
const guard = "/home/test/.pi/agent/extensions/command-guards.ts";
const expectedProfiles = {
  explorer: ["openai-codex/gpt-6-luna", "high"],
  worker: ["openai-codex/gpt-6.1-sol", undefined],
  "small-worker": ["openai-codex/gpt-6-luna", "high"],
  reviewer: ["claude-code-cli/opus", "high"],
};
const settings = () => json("./subagents/config.json");
const profiles = () => json("./subagents/profiles.json");
const prompt = (role) =>
  read(`./subagents/${role === "small-worker" ? "worker" : role}.md`);
const fields = (name, profile) => ({
  ...profile,
  name,
  extensions: [guard],
  skills: true,
  allowed_subagents: false,
  prompt_mode: "replace",
  inherit_context: false,
  isolation: "off",
});
const render = (name, profile) =>
  `---\n${Object.entries(fields(name, profile))
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}: ${JSON.stringify(value)}`)
    .join("\n")}\n---\n\n${read("../AGENTS.md")}\n${prompt(name)}`;

function temporary(t) {
  const directory = mkdtempSync(join(tmpdir(), "pi-subagents-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return directory;
}

test("upstream settings disable fallback, nesting, Git isolation, and optional orchestrators", () => {
  assert.deepEqual(settings(), {
    maxConcurrent: 4,
    maxConcurrentForeground: 2,
    maxSubagentDepth: 1,
    fallbackSubagent: "none",
    disableDefaultAgents: true,
    worktreeIsolation: false,
    schedulingEnabled: false,
    workflowsEnabled: false,
    packageAgents: false,
    packageWorkflows: false,
    backgroundByDefault: true,
    widgetMode: "all",
    fleetView: true,
    showModel: true,
  });
});

test("Home Manager deploys stock upstream settings and standalone Markdown agents", () => {
  const module = read("../pi.nix");
  assert.match(module, /npm:@tintinweb\/pi-subagents@0\.22\.0/);
  assert.match(
    module,
    /"\.pi\/agent\/subagents\.json"\.text = builtins\.toJSON subagentSettings/,
  );
  assert.match(module, /"\.pi\/agent\/agents\/\$\{name\}\.md"/);
  assert.match(module, /builtins\.readFile \.\/pi\/subagents\/profiles\.json/);
  assert.match(module, /builtins\.readFile \.\/AGENTS\.md/);
  assert.match(
    module,
    /extensions = \[ "\$\{config\.home\.homeDirectory\}\/\.pi\/agent\/extensions\/command-guards\.ts" \]/,
  );
  for (const fragment of [
    "skills = true",
    "allowed_subagents = false",
    'prompt_mode = "replace"',
    "inherit_context = false",
    'isolation = "off"',
  ])
    assert.ok(module.includes(fragment), fragment);
  assert.doesNotMatch(
    module,
    /pi-actor-subagents|actor-subagents|roles\.json|childExtensions/,
  );
  assert.deepEqual(
    Object.keys(profiles()).sort(),
    Object.keys(expectedProfiles).sort(),
  );
  for (const [role, [model, thinking]] of Object.entries(expectedProfiles)) {
    const profile = profiles()[role];
    assert.equal(profile.model, model);
    assert.equal(profile.thinking, thinking);
    assert.equal(
      profile.tools,
      ["explorer", "reviewer"].includes(role)
        ? "read, grep, find, ls"
        : "read, bash, edit, write, grep, find, ls",
    );
    assert.ok(profile.description);
    assert.match(prompt(role), /Work directly without delegating/);
    assert.match(prompt(role), /absolute.*workspace|absolute paths rooted/);
    assert.doesNotMatch(
      prompt(role),
      /handshake|send_message|set_status|go-ahead/,
    );
    assert.match(render(role, profile), /^---\n/);
  }
  for (const fragment of [
    "Keep the workspace unchanged",
    "execution path",
    "file and symbol references",
    "uncertainty",
    "Stop when the question is answered",
  ])
    assert.ok(prompt("explorer").includes(fragment), fragment);
  assert.match(prompt("reviewer"), /Keep the workspace unchanged/);
});

test("activation replaces legacy packages and removes obsolete inline settings", (t) => {
  const directory = temporary(t);
  const target = join(directory, "settings.json");
  const defaults = join(directory, "defaults.json");
  const managed = { packages: ["npm:@tintinweb/pi-subagents@0.22.0"] };
  writeFileSync(defaults, JSON.stringify(managed));
  for (const source of [
    "npm:pi-subagents@0.82.1",
    "npm:pi-actor-subagents@0.1.32",
  ]) {
    writeFileSync(
      target,
      JSON.stringify({
        editorPaddingX: 3,
        packages: [source],
        subagents: { disableBuiltins: true },
      }),
    );
    execFileSync("python3", [
      new URL("./settings.py", import.meta.url).pathname,
      target,
      defaults,
    ]);
    assert.deepEqual(JSON.parse(readFileSync(target, "utf8")), {
      editorPaddingX: 3,
      ...managed,
    });
  }
});

test(
  "evaluated Home Manager deployment matches rendered agents",
  { skip: !process.env.PI_SUBAGENTS_DEPLOYMENT },
  () => {
    const deployed = JSON.parse(
      readFileSync(process.env.PI_SUBAGENTS_DEPLOYMENT, "utf8"),
    );
    assert.deepEqual(JSON.parse(deployed.settings), settings());
    assert.deepEqual(
      Object.keys(deployed.agents).sort(),
      Object.keys(expectedProfiles).sort(),
    );
    for (const [role, profile] of Object.entries(profiles()))
      assert.equal(deployed.agents[role], render(role, profile));
  },
);

test(
  "public upstream loader accepts settings and rendered role definitions",
  {
    skip: !process.env.PI_SUBAGENTS_DIR,
  },
  async (t) => {
    // Pi's loader resolves TypeScript and host packages; native Node cannot load installed .ts files.
    assert.ok(
      process.env.PI_JITI_MODULE,
      "PI_JITI_MODULE must name Pi's jiti module",
    );
    assert.ok(
      process.env.PI_CODING_AGENT_MODULE,
      "PI_CODING_AGENT_MODULE must name Pi's host module",
    );
    const directory = temporary(t);
    const agentDir = join(directory, "agent");
    const cwd = join(directory, "project");
    mkdirSync(join(agentDir, "agents"), { recursive: true });
    mkdirSync(cwd);
    const old = process.env.PI_CODING_AGENT_DIR;
    process.env.PI_CODING_AGENT_DIR = agentDir;
    t.after(() => {
      if (old === undefined) delete process.env.PI_CODING_AGENT_DIR;
      else process.env.PI_CODING_AGENT_DIR = old;
    });
    for (const [role, profile] of Object.entries(profiles()))
      writeFileSync(
        join(agentDir, "agents", `${role}.md`),
        render(role, profile),
      );
    writeFileSync(join(agentDir, "subagents.json"), JSON.stringify(settings()));
    const { createJiti } = await import(
      pathToFileURL(process.env.PI_JITI_MODULE).href
    );
    const jiti = createJiti(import.meta.url, {
      fsCache: false,
      alias: {
        "@earendil-works/pi-coding-agent": process.env.PI_CODING_AGENT_MODULE,
      },
    });
    const upstream = (file) =>
      jiti.import(join(process.env.PI_SUBAGENTS_DIR, "src", file));
    const { loadCustomAgents } = await upstream("custom-agents.ts");
    const { loadSettings } = await upstream("settings.ts");
    assert.deepEqual(loadSettings(cwd), settings());
    const agents = loadCustomAgents(cwd, true, {
      packageDirs: [],
      packageFiles: [],
    });
    assert.deepEqual(
      [...agents.keys()].sort(),
      Object.keys(expectedProfiles).sort(),
    );
    for (const [role, profile] of Object.entries(profiles())) {
      const agent = agents.get(role);
      assert.equal(agent.model, profile.model);
      assert.equal(agent.thinking, profile.thinking);
      assert.deepEqual(agent.builtinToolNames, profile.tools.split(", "));
      assert.deepEqual(agent.extensions, [guard]);
      assert.equal(agent.skills, true);
      assert.equal(agent.allowedSubagents, undefined);
      assert.equal(agent.inheritContext, false);
      assert.equal(agent.promptMode, "replace");
      assert.equal(agent.isolation, "off");
      assert.equal(
        agent.systemPrompt,
        `${read("../AGENTS.md")}\n${prompt(role)}`.trim(),
      );
    }
  },
);

test("deploys Oyo alone without changing one-shot child roles or Darwin browser scope", () => {
  const module = read("../pi.nix");
  assert.match(
    module,
    /config\.agents\.pi\.skills =\s*\{\s*feature = \.\/pi\/skills\/feature;\s*\}\s*\/\/ lib\.optionalAttrs/,
  );
  assert.match(
    module,
    /lib\.optionalAttrs pkgs\.stdenv\.isDarwin \{\s*agent-browser/,
  );
  const brew = read("../../../hosts/macbook/homebrew.nix");
  assert.match(brew, /"ahkohd\/oyo\/oy"/);
  assert.match(brew, /trustedtaps = names config\.homebrew\.taps/);
  assert.match(brew, /trustedformulae = qualified config\.homebrew\.brews/);
});

test("first-party review bridge deploys only to parents without an extra Pi package", () => {
  const module = read("../pi.nix");
  assert.match(
    module,
    /extensions = \[ "\$\{config\.home\.homeDirectory\}\/\.pi\/agent\/extensions\/command-guards\.ts" \]/,
  );
  assert.match(
    module,
    /"\.pi\/agent\/extensions\/oyo-review"\.source = \.\/pi\/oyo-review/,
  );
  assert.doesNotMatch(module, /npm:.*pi-oyo|extensions\/hunk-review/);
  const flake = read("../../../flake.nix");
  assert.match(flake, /pi-oyo-review/);
  assert.ok(
    flake.includes(
      "node --experimental-strip-types --test ${./.}/home/agents/pi/oyo-review.test.mjs",
    ),
  );
  const entry = read("./oyo-review/index.ts");
  assert.match(entry, /import \{ Type \} from "@earendil-works\/pi-ai"/);
  assert.match(
    entry,
    /import type \{ ExtensionAPI \} from "@earendil-works\/pi-coding-agent"/,
  );
  assert.match(entry, /registerOyoWatch\(pi, Type\)/);
  for (const role of Object.keys(expectedProfiles))
    assert.deepEqual(fields(role, profiles()[role]).extensions, [guard]);
});
