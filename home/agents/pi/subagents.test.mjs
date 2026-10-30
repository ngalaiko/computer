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

test("feature orchestration requires explicit activation", () => {
  const defaults = read("./AGENTS.md");
  assert.doesNotMatch(
    defaults,
    /<delegation>|workspace add|oyo-review|feature-tabs|oyo_watch/,
  );
  assert.match(defaults, /explicit.*\/skill:feature/i);
  const feature = read("./skills/feature/SKILL.md");
  assert.match(feature, /^---\nname: feature\ndescription:/);
  assert.match(feature, /disable-model-invocation: true/);
  assert.match(defaults, /coordinator.*inherits activation.*same task/i);
  assert.match(
    feature,
    /coordinator launched for that task inherits activation/i,
  );
  assert.match(
    feature,
    /Resolve their links relative to this file's directory/i,
  );
  assert.match(feature, /\[.*\]\(oyo-review\.md\)/);
  assert.match(feature, /\[.*\]\(feature-tabs\.md#tab-title\)/);
  const module = read("../pi.nix");
  assert.doesNotMatch(module, /(?:oyo-review|feature-tabs) = \.\/pi\/skills\//);
});

test("upstream settings disable fallback, nesting, Git isolation, and optional orchestrators", () => {
  assert.deepEqual(settings(), {
    maxConcurrent: 2,
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

test("parent orchestration is one-shot, event-driven, and explicit about JJ paths", () => {
  const instructions = read("./skills/feature/SKILL.md");
  assert.doesNotMatch(read("../AGENTS.md"), /<delegation>/);
  for (const fragment of [
    "Parent Pi sessions coordinate this workflow",
    "Child agents follow their assigned role",
    "get_subagent_result",
    "steer_subagent",
    "thinking",
    "`medium`",
    "`high`",
    "Bounded codebase questions and noisy investigation; read-only",
    "escalate ambiguity to `worker`",
    "Goal, scope, constraints and completion evidence",
    "Assigned absolute workspace and file paths",
    "Expected result and stop condition",
    "Start a fresh reviewer for each independent review",
    "without implementation conversations or another agent's review history",
    "git.colocate=false workspace add",
    "children retain the parent's cwd",
    "absolute",
    "prompt-only",
    "two",
    "completion notification",
    "rather than polling",
    "persistent task workspace",
    "default/source workspace untouched",
    "[Oyo review — Task workspace](oyo-review.md#task-workspace) before repository edits or writer launches",
  ])
    assert.ok(instructions.includes(fragment), fragment);
  assert.doesNotMatch(
    instructions,
    /integration and workspace deletion require explicit operator approval|both require operator approval/i,
  );
  assert.doesNotMatch(
    instructions,
    /spawn_subagent|send_message|handshake|roles\.json|pause_subagents|kill_subagents/,
  );
  const worker = read("./subagents/worker.md");
  assert.match(worker, /Integration requires explicit operator approval/);
  assert.match(
    worker,
    /parent owns cleanup authorization and final verification/,
  );
  assert.match(worker, /supplied finishing contract/);
  assert.doesNotMatch(
    worker,
    /integration and workspace deletion require explicit operator approval|both require operator approval/i,
  );
  const docs = read("./README.md");
  for (const fragment of [
    "maxConcurrentForeground",
    "separate",
    "resume",
    "options.cwd",
    "prompt-only",
    "unavailable",
    "/agents",
    "not migrated",
  ])
    assert.ok(docs.includes(fragment), fragment);
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
  assert.match(read("./skills/feature/SKILL.md"), /oyo-review/);
  assert.match(
    read("./skills/feature/oyo-review.md"),
    /from readiness.*user says done/i,
  );
  assert.match(read("./skills/feature/SKILL.md"), /assigning one-shot tasks/i);
  assert.doesNotMatch(prompt("worker"), /oyo|walkthrough/i);
});

test("ready child reviews open automatically and retain the integration gate", () => {
  const skill = read("./skills/feature/oyo-review.md");
  const parent = read("./skills/feature/SKILL.md");
  assert.match(skill, /^# Oyo review/);
  assert.doesNotMatch(skill, /disable-model-invocation: true/);
  assert.match(
    parent,
    /Read \[Oyo review\]\(oyo-review\.md\) before opening the child diff/i,
  );
  assert.match(
    skill,
    /After child exit and tests\/reviewer finish.*open review automatically/i,
  );
  assert.match(
    read("./skills/feature/finishing.md"),
    /Integration requires explicit operator approval/,
  );
  assert.match(skill, /\[Finishing\]\(finishing\.md\) before integration/);
  assert.match(skill, /Wait for questions, feedback or `next`/);
  assert.doesNotMatch(
    skill,
    /offer a walkthrough|explicit skip|ask whether.*finished|ask for.*integration approval/i,
  );
  assert.match(
    read("./skills/feature/finishing.md"),
    /explicit integration approval and verified integration.*remove redundant task resources/i,
  );
});

test("Rex launches the resolved executable rather than relying on login PATH", () => {
  const skill = read("./skills/feature/oyo-review.md");
  assert.ok(skill.includes("oy_bin=$(command -v oy)"));
  assert.match(skill, /absolute.*executable|executable.*absolute/);
  const split = skill.split("\n").find((line) => line.startsWith("rex split "));
  assert.ok(split);
  assert.ok(split.includes('--split=right --ratio 67 -c "$workspace"'));
  assert.ok(split.includes('-- "$oy_bin" @ --session "$review_session"'));
  assert.doesNotMatch(split, /-- oy(?:\s|$)/);
  assert.match(
    skill,
    /process exited.*close only.*task-created failed pane.*retry/i,
  );
  assert.match(skill, /timeout.*inspect.*before.*retry/i);
});

test("pending reviews survive turns and only task-owned panes close on done", () => {
  const skill = read("./skills/feature/oyo-review.md");
  assert.match(skill, /from readiness.*across user turns.*user says done/i);
  assert.match(skill, /user says done.*close only.*task-created split/i);
  assert.ok(
    skill.includes('rex block close -s "$REX_SESSION" "$review_block"'),
  );
  assert.match(skill, /terminated before cleanup/i);
  assert.match(skill, /preexisting.*pane/i);
  assert.match(skill, /named JJ bookmark/);
  assert.match(skill, /UI only.*await user instruction/i);
});

test("review uses installed docs and separate control/data interfaces", () => {
  const skill = read("./skills/feature/oyo-review.md");
  for (const command of [
    "rex skill show",
    '"$oy_bin" skill path',
    '"$oy_bin" skill path control',
    '"$oy_bin" skill path walkthrough',
    '"$oy_bin" --help',
    '"$oy_bin" control get --session "$review_session" --json',
    '"$oy_bin" control diff --session "$review_session" --json',
    '"$oy_bin" control where --session "$review_session" --json',
    '"$oy_bin" review status -t @ --json',
    '"$oy_bin" review comment -t @ --json',
  ])
    assert.ok(skill.includes(command), command);
  assert.match(skill, /retarget unrelated sessions/i);
  assert.match(skill, /never impersonate the human/i);
  assert.match(skill, /publication.*specific operator consent/i);
  assert.match(skill, /resume.*one-shot.*retest.*fresh independent review/i);
  for (const command of [
    '"$oy_bin" control goto --session "$review_session" --file PATH --new-line N',
    '"$oy_bin" control target --session "$review_session" @',
  ])
    assert.ok(skill.includes(command), command);
  assert.doesNotMatch(skill, /control goto[^\n]*--json/);
  assert.doesNotMatch(skill, /control target[^\n]*--json/);
  assert.doesNotMatch(skill, /\/private\/tmp\//);
});

test("feature tabs deploy and route to independent interactive coordinators", () => {
  const module = read("../pi.nix");
  assert.match(module, /feature = \.\/pi\/skills\/feature/);
  assert.match(
    read("./skills/feature/SKILL.md"),
    /Read \[Feature tabs\].*starting a separate interactive coordinator; another tab is optional/i,
  );
  assert.match(
    read("./skills/feature/SKILL.md"),
    /persistent task workspace.*retain its identity across review rounds/i,
  );
  const skill = read("./skills/feature/feature-tabs.md");
  assert.match(skill, /^# Feature tabs/);
  assert.doesNotMatch(skill, /disable-model-invocation: true/);
  assert.match(skill, /actionable.*feature brief/);
  assert.match(skill, /explicit feature-workflow activation/);
  assert.match(
    skill,
    /feature_skill="\$HOME\/\.pi\/agent\/skills\/feature\/SKILL\.md"/,
  );
  assert.match(skill, /test -r "\$feature_skill"/);
  assert.match(skill, /substitute.*absolute.*feature_skill.*brief/i);
  assert.match(skill, /not an Agent role or background subagent/i);
  assert.ok(skill.includes("pi_bin=$(command -v pi)"));
  assert.ok(
    skill.includes(
      'rex window new -s "$REX_SESSION" "$feature_label" -c "$feature_cwd" --json -- "$pi_bin" --name "$feature_label" -- "$brief"',
    ),
  );
  const launch = skill
    .split("\n")
    .find((line) => line.startsWith("rex window new -s"));
  assert.doesNotMatch(launch, /sh -c|--print|--resume|--continue|--inherit/);
  assert.match(skill, /oyo-review.*Task workspace.*before tab launch/);
  assert.match(skill, /source-relative subdirectory/);
  assert.match(skill, /own.*REX_SESSION.*REX_BLOCK.*never.*caller/i);
  assert.match(skill, /process.*capture|capture.*process/i);
  assert.match(skill, /timeout.*inspect.*retry/i);
  assert.match(skill, /keep.*workspace.*alive.*Pi or tab.*active/i);
});

test("review stays beside its feature Pi and never closes the coordinator", () => {
  const skill = read("./skills/feature/oyo-review.md");
  assert.match(skill, /owning feature Pi.*same tab/i);
  assert.match(skill, /never.*app focus.*another feature tab/i);
  assert.match(skill, /never.*Pi tab or feature coordinator workspace/i);
  assert.match(
    read("./skills/feature/SKILL.md"),
    /Child cleanup excludes the PR coordinator/,
  );
});

test("integrated cleanup removes task-owned refs and revisions; pending work stays recoverable", () => {
  const parent = read("./skills/feature/SKILL.md");
  const review = read("./skills/feature/finishing.md");
  const feature = read("./skills/feature/feature-tabs.md");
  assert.match(parent, /Finishing.*before integration or cleanup/i);
  for (const fragment of [
    "explicit integration approval",
    "verified integration",
    "user completion",
    "record task ownership, exact bookmark/workspace names, full change IDs",
    "Scope every JJ ref/revision operation to those recorded task resources",
    "redundant task-owned revisions",
    "superseded implementation copies",
    "empty successors",
    "superseded trials",
    "exact workspace directory",
    "jj workspace forget",
    "unrelated bookmarks/remotes",
    "active/shared/source workspaces",
    "pending, unintegrated, or failed work",
    "named recoverable bookmark",
    "operator explicitly discards",
    "permanent backup or review-bookmark clutter",
  ])
    assert.ok(review.includes(fragment), fragment);
  assert.match(review, /disposable child workspaces/i);
  assert.match(
    review,
    /Preserve the consolidated PR revision and its ancestors/i,
  );
  assert.match(
    review,
    /Retain the persistent PR task workspace across review rounds and revisions/i,
  );
  assert.match(review, /Closing a child review does not end the PR/i);
  assert.match(
    review,
    /including after child review closure or approved consolidation/i,
  );
  assert.match(
    review,
    /verified termination of task-owned UI, watches and processes/i,
  );
  assert.match(review, /Cleanup never integrates or pushes/i);
  assert.match(
    review,
    /PR.*ended.*dedicated feature Pi\/tab.*exit.*independently verifies termination/i,
  );
  assert.match(review, /Preserve the pending or failed revision and bookmark/i);
  assert.doesNotMatch(
    review,
    /every approved workspace commit boundary|Cleanup never combines approved workspace commits|forget only the exact task workspace/,
  );
  assert.match(
    feature,
    /Pi and tab to exit.*independently verify termination/i,
  );
  assert.match(feature, /after verified integration/i);
  assert.match(feature, /preserve.*pending|pending.*preserve/i);
});

test("feature startup recovery reuses its workspace and reports recovery IDs", () => {
  const skill = read("./skills/feature/feature-tabs.md");
  assert.match(skill, /retry.*same already-created feature workspace/i);
  assert.match(
    skill,
    /failure report.*workspace path\/name.*session\/tab\/block IDs/i,
  );
});

test("feature launch requires an actionable request and executable Pi", () => {
  const skill = read("./skills/feature/feature-tabs.md");
  assert.match(
    skill,
    /Launch only for an actionable user feature request, not a request to configure this workflow/,
  );
  assert.ok(skill.includes('test -x "$pi_bin"'));
});

test("coordinator teardown waits for user exit and verification elsewhere", () => {
  const skill = read("./skills/feature/feature-tabs.md");
  assert.match(skill, /user explicitly ends the feature/);
  assert.match(skill, /Pi and tab to exit/i);
  assert.match(
    skill,
    /another session to independently verify termination before teardown/i,
  );
  assert.match(skill, /never remove.*live coordinator cwd/i);
});

test("worker working-copy contract keeps child review target at @", () => {
  assert.match(
    prompt("worker"),
    /Implementation tasks keep changes in the working-copy change/,
  );
  const skill = read("./skills/feature/oyo-review.md");
  assert.match(skill, /Use `@` for this child-only diff/);
  assert.ok(
    skill.includes('"$oy_bin" control target --session "$review_session" @'),
  );
  assert.doesNotMatch(skill, /control target[^\n]*--json/);
  assert.match(skill, /sole bookmark.*stack/i);
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

test("automatic feedback preserves native roots and human resolution", () => {
  const parent = read("./skills/feature/SKILL.md");
  const skill = read("./skills/feature/oyo-review.md");
  assert.match(
    parent,
    /For saved feedback, follow Oyo review's discussion and native-reply procedure/i,
  );
  for (const text of [
    '"$oy_bin" review comment reply -t @ ID --body',
    "OYO_REVIEW_AUTHOR_TYPE=agent",
    "OYO_REVIEW_AUTHOR_NAME=Pi",
    '"$oy_bin" review comment -t @ --unresolved --json',
    '"$oy_bin" review comment -t @ --unresolved --outdated --json',
  ])
    assert.ok(skill.includes(text), text);
  assert.match(skill, /same thread root/i);
  assert.match(skill, /replies support only.*non-outdated.*line.*hunk/i);
  assert.match(skill, /outdated.*file-level.*deleted/i);
  assert.match(skill, /report.*chat.*thread ID/i);
  assert.match(skill, /never.*detached comment.*clear.*outdated/i);
  assert.match(skill, /Only the human.*resolves\/reopens/i);
  assert.match(skill, /local policy.*not.*API/i);
  assert.match(skill, /thread roots, not replies/i);
  assert.match(skill, /missing.*query.*unknown, not zero/i);
  assert.match(skill, /outdated.*snapshots/i);
  assert.match(skill, /never.*goto.*outdated/i);
  assert.match(skill, /answer, edit, or test outcome/i);
  assert.match(skill, /never claim it posted.*uncertain write/i);
  assert.match(skill, /user request.*checkpoints/i);
  for (const fragment of [
    "oyo_watch",
    'action: "start"',
    'action: "stop"',
    "oyBin",
    "exact native session",
    "initial result",
    "delivery inactive",
    "Pi reload",
    "no auto-resume",
    "Status-only",
    "coalesce",
    "created and deleted",
    "not an exact hook/event journal",
  ])
    assert.ok(skill.includes(fragment), fragment);
  assert.match(skill, /stop.*watcher.*before.*clos/i);
  assert.match(read("./README.md"), /deployed.*reload|reload.*deployed/is);
});

test("Oyo identity is snapshot guarded without fabricated metadata", () => {
  const skill = read("./skills/feature/oyo-review.md");
  for (const text of [
    "jj log -r @ --no-graph -T commit_id",
    "jj log -r @ --no-graph -T change_id",
    "jj diff -r @ --summary",
    "workspaceRoot",
    "target",
    "reviewKey",
    "diffFingerprint",
    "lastAppliedSeq",
    "lastError",
    "PID",
    "cwd",
  ])
    assert.ok(skill.includes(text), text);
  assert.match(skill, /before and after.*loading/i);
  assert.match(skill, /exact file paths.*jj diff -r @ --summary/i);
  assert.match(skill, /identity.*cannot.*establish.*stop/i);
  assert.match(skill, /no dedicated.*full commit.*provider/i);
  assert.match(skill, /empty.*report.*stop/i);
  assert.match(skill, /before.*bookmark.*open/i);
  assert.match(skill, /lastError.seq.*>=.*seq/);
  assert.match(skill, /lastAppliedSeq.*>=.*seq/);
  assert.match(skill, /human input.*priority/i);
  assert.match(
    skill,
    /recheck the unchanged JJ commit, change_id and summary/i,
  );
  assert.match(skill, /\.data\.target == @/);
  assert.match(skill, /status target.*working tree/i);
  assert.match(skill, /not by requiring equality with control/i);
  assert.match(skill, /reviewKey.*short.*change.*prefix/i);
  assert.match(skill, /mutations.*print text, not JSON/i);
  assert.match(skill, /save its printed `seq`/i);
  assert.match(skill, /intended cursor.*target and matching control metadata/i);
  assert.match(skill, /inReplyTo/);
  assert.match(
    skill,
    /Oyo 0\.1\.61.*includePatch.*no raw patch|includePatch.*no raw patch.*Oyo 0\.1\.61/i,
  );
  assert.match(
    skill,
    /control target.*@.*sequence-application guard.*metadata.*exact file coverage/i,
  );
  assert.match(skill, /JJ snapshot.*before and after/i);
  assert.match(skill, /optional.*Rex capture/i);
  assert.match(skill, /file counters do not prove patch content/i);
  assert.doesNotMatch(skill, /include.*--include-patch.*raw diff is needed/i);
  assert.match(skill, /For each queued command.*printed `seq`.*absent.*stop/i);
  assert.match(
    skill,
    /Require `lastAppliedSeq >= seq` before dependent commands/i,
  );
  assert.match(skill, /Ignore older `lastError` values/i);
  assert.doesNotMatch(
    skill,
    /printed `seq` if available|no `lastError` before dependent commands/,
  );
  assert.doesNotMatch(skill, /loaded patch.*jj diff --git -r @/i);
});

test("PR integration consolidates approved work only in its persistent task workspace", () => {
  const parent = read("./skills/feature/SKILL.md");
  const review = read("./skills/feature/finishing.md");
  const feature = read("./skills/feature/feature-tabs.md");
  assert.match(
    parent,
    /For a PR, consolidate approved changes in the persistent task workspace/i,
  );
  assert.match(parent, /default\/source workspace.*untouched/i);
  assert.match(parent, /Finishing.*before integration or cleanup/i);
  assert.match(
    review,
    /one JJ revision.*PR.*task workspace.*unless the operator specifies otherwise/i,
  );
  assert.match(review, /different child workspaces for the same PR/i);
  assert.match(review, /Never combine different PRs/i);
  assert.match(
    review,
    /Never integrate into or move the default\/source workspace/i,
  );
  assert.match(review, /approved identity\/review\/tests/i);
  assert.match(review, /conflicts.*tests\/independent review/i);
  assert.match(
    review,
    /Record the integrated full change\/commit IDs and verify history\/tree/i,
  );
  assert.match(feature, /feature lifetime is the PR lifetime/i);
  assert.match(
    feature,
    /Reuse the existing PR task workspace across review rounds and revisions/i,
  );
  assert.match(feature, /new tab only under the launch conditions above/i);
  assert.match(feature, /temporary writer workspaces remain separate/i);
  for (const instructions of [parent, review]) {
    assert.doesNotMatch(
      instructions,
      /distinct JJ commit\/change|jj new <integrated-change>|never squash a child|combine different workspaces|every approved workspace commit boundary|Move source to a new empty descendant|automatically cleaning the parent's own task workspace/,
    );
  }
  assert.match(
    prompt("worker"),
    /Integration requires explicit operator approval/,
  );
});

test("integration stops delivery before mutation and rejects multi-change children", () => {
  const instructions = read("./skills/feature/finishing.md");
  assert.match(instructions, /Integration requires explicit operator approval/);
  assert.match(
    instructions,
    /stop.*oyo_watch.*verify.*stopped.*before any integration rebase or consolidation/i,
  );
  assert.match(instructions, /multi-change child.*stop.*report.*ask/i);
  assert.match(instructions, /never silently integrate only `@`/i);
  assert.match(instructions, /resume.*explicitly.*reverified.*UI/i);
  const readme = read("./README.md");
  assert.match(readme, /provider-backed.*bodies.*filter/is);
  assert.match(readme, /stoppedReason/);
  assert.match(
    readme,
    /read commands.*reconcile persisted anchors\/author metadata/is,
  );
});

test("owning parent keeps its Rex tab title aligned with task activity", () => {
  const parent = read("./skills/feature/SKILL.md");
  const feature = read("./skills/feature/feature-tabs.md");
  assert.match(
    parent,
    /Keep a concise task \+ activity tab title on meaningful phase changes/i,
  );
  assert.match(parent, /Feature tabs.*ownership checks and updates/i);
  assert.match(parent, /meaningful phase changes.*feature-tabs/i);
  assert.match(feature, /feature_label.*initial title.*owning Pi.*updates/i);
  for (const fragment of [
    'rex block inspect -s "$REX_SESSION" "$REX_BLOCK" --json',
    ".block.window_id",
    'rex window rename -s "$REX_SESSION" "$window_id" "$title"',
    "implementing",
    "testing",
    "review",
    "blocked",
    "done",
    "rex skill show",
    "rex window rename --help",
  ])
    assert.ok(feature.includes(fragment), fragment);
  assert.match(feature, /verify.*own.*REX_SESSION.*REX_BLOCK/i);
  assert.match(feature, /Never rename.*session.*unrelated.*focused tab/i);
  assert.match(feature, /meaningful phase changes.*not per command/i);
  assert.match(feature, /No Rex.*nonblocking.*report failures/i);
  assert.match(feature, /without creating UI or guessing IDs/i);
  assert.match(
    feature,
    /`review-flow: implementing`, `testing`, `review`, `blocked`, or `done`/,
  );
});

test("task setup precedes writers without requiring a new Pi or tab", () => {
  const parent = read("./skills/feature/SKILL.md");
  const review = read("./skills/feature/oyo-review.md");
  const setup = review.split("## Task workspace")[1]?.split("## Prepare")[0];
  assert.ok(setup, "authoritative setup procedure");
  assert.match(
    parent,
    /Read \[Oyo review — Task workspace\]\(oyo-review\.md#task-workspace\) before repository edits or writer launches/,
  );
  assert.match(
    parent,
    /Create or verify one persistent task workspace and its ownership record/,
  );
  assert.match(parent, /Require explicit operator approval to integrate/);
  assert.match(setup, /without launching another Pi or tab/i);
  assert.match(
    setup,
    /empty workspace.*does not require integration approval/i,
  );
  assert.match(setup, /stable unique task key before.*PR exists/i);
  assert.match(setup, /repository identity.*PR URL when available/i);
  for (const command of [
    "jj workspace list",
    "jj bookmark list",
    "jj log",
    "jj bookmark create",
    "jj --config git.colocate=false workspace add",
  ])
    assert.ok(setup.includes(command), command);
  assert.match(setup, /persistent task bookmark.*task\//i);
  assert.match(setup, /~\/.pi\/agent\/jj-workspaces\/<key>\.json/);
  assert.match(
    setup,
    /record.*task key.*repository.*PR URL.*workspace name.*path.*bookmark/i,
  );
  assert.match(setup, /No task metadata.*commit messages/i);
  assert.doesNotMatch(setup, /jj describe|identity.*JJ change description/);
  assert.match(setup, /across sessions.*record.*bookmark.*jj workspace list/i);
  assert.match(setup, /verify.*recorded.*paths.*identity.*ask on ambiguity/i);
  assert.match(setup, /cd "\$task_workspace" &&/);
  assert.match(setup, /default\/source.*unchanged/i);
  assert.match(setup, /before launching writers/i);
});

test("persistent PR identity survives consolidation and coordinator teardown", () => {
  const review = read("./skills/feature/finishing.md");
  const feature = read("./skills/feature/feature-tabs.md");
  assert.match(
    review,
    /persistent task bookmark.*follow.*consolidated PR revision/i,
  );
  assert.match(review, /ownership record.*survives.*teardown/i);
  assert.match(
    review,
    /persistent PR bookmark.*survives coordinator teardown/i,
  );
  assert.match(
    review,
    /local child consolidation.*not.*integration.*target history/i,
  );
  assert.match(
    review,
    /delete.*persistent.*bookmark.*only after.*actual PR integration.*target history.*verified/i,
  );
  assert.match(
    review,
    /temporary review bookmarks.*distinct from.*persistent PR bookmark/i,
  );
  assert.match(review, /sole PR ref/i);
  assert.match(feature, /oyo-review.*Task workspace.*before.*launch/i);
  assert.match(feature, /Continue in its existing tab when live/i);
  assert.match(feature, /Ambiguous ownership blocks launch/i);
  assert.match(feature, /Child cleanup excludes this coordinator workspace/i);
});

test("task lifecycle uses local ownership and quiescent working copies", () => {
  const parent = read("./skills/feature/SKILL.md");
  const review = [
    read("./skills/feature/oyo-review.md"),
    read("./skills/feature/finishing.md"),
  ].join("\n");
  const feature = read("./skills/feature/feature-tabs.md");
  assert.ok(
    parent.includes(
      'cd "$task_workspace" && jj --config git.colocate=false workspace add',
    ),
  );
  assert.match(
    review,
    /Remove the ownership record only when.*PR bookmark.*safely removed or.*discarded/i,
  );
  assert.match(review, /dedicated feature Pi\/tab.*exit.*independent/i);
  assert.match(
    review,
    /external parent.*no process cwd, UI, watch or active child.*exact task workspace/i,
  );
  assert.match(review, /Do not close the external parent.*Pi or tab/i);
  assert.match(
    review,
    /Before rewriting.*integration or coordinator direct edits.*stop or finish.*writers.*watchers.*reviews.*descendants/i,
  );
  assert.match(
    review,
    /jj workspace update-stale.*only after.*ownership verification and worker exit/i,
  );
  assert.match(review, /rerun.*snapshot identity.*tests.*review/i);
  assert.match(
    review,
    /stable intended base.*mutable default\/source.*unrelated.*ask if ambiguous/i,
  );
  assert.match(
    feature,
    /own pane.*ownership evidence.*current task context.*title/i,
  );
  assert.match(feature, /No separate task-tab registry/i);
});

test("cleanup scope, review refs, coordinator discovery and parent paths stay explicit", () => {
  const parent = read("./skills/feature/SKILL.md");
  const review = [
    read("./skills/feature/oyo-review.md"),
    read("./skills/feature/finishing.md"),
  ].join("\n");
  const feature = read("./skills/feature/feature-tabs.md");
  assert.match(
    review,
    /jj workspace forget.*only the exact disposable child workspace/i,
  );
  assert.match(
    review,
    /PR has ended.*process gates.*jj workspace forget.*exact coordinator.*exact directory/is,
  );
  assert.match(
    review,
    /update the temporary child review bookmark; keep the persistent task bookmark on the approved consolidated PR revision/i,
  );
  assert.match(
    review,
    /optional dedicated coordinator runtime fields.*Rex session\/window\/block.*PID/i,
  );
  assert.match(feature, /save.*runtime fields.*after verified launch/i);
  assert.match(feature, /recorded Rex IDs.*process cwd.*identity.*PID reuse/i);
  assert.match(
    feature,
    /missing or stale.*process cwds.*Rex listing.*ambiguity blocks launch/i,
  );
  assert.match(feature, /never launch a duplicate live coordinator/i);
  assert.match(
    parent,
    /Use absolute task-workspace-rooted paths for parent file tools/i,
  );
  assert.match(
    review,
    /parent file tools.*absolute task-workspace-rooted paths.*relative read\/edit\/write.*default/i,
  );
});
