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
  const instructions = read("./AGENTS.md");
  assert.doesNotMatch(read("../AGENTS.md"), /<delegation>/);
  for (const fragment of [
    "Parent Pi sessions only",
    "Agent",
    "subagent_type",
    "get_subagent_result",
    "steer_subagent",
    "thinking",
    '"medium"',
    '"high"',
    "Use explorer for bounded codebase questions",
    "Escalate ambiguous small-worker tasks to worker",
    "goal, scope, constraints, paths, expected evidence, and stop condition",
    "Start a new reviewer",
    "not the implementation conversation",
    "git.colocate=false workspace add",
    "Children retain the parent's cwd",
    "absolute",
    "prompt-only",
    "two",
    "completion notification",
    "rather than polling",
    "Integration requires explicit operator approval",
    "automatically cleaning the parent's own task workspace",
    "After child exit and reviews/tests finish",
    "named recoverable bookmark",
    "jj workspace forget",
    "active/shared/source workspaces",
    "Report cleanup failures",
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
  assert.match(worker, /parent owns automatic cleanup/);
  assert.match(worker, /parent cleanup policy/);
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
    /config\.agents\.pi\.skills =\s*\{\s*feature-tabs = \.\/pi\/skills\/feature-tabs;\s*oyo-review = \.\/pi\/skills\/oyo-review;\s*\}\s*\/\/ lib\.optionalAttrs/,
  );
  assert.match(
    module,
    /lib\.optionalAttrs pkgs\.stdenv\.isDarwin \{\s*agent-browser/,
  );
  const brew = read("../../../hosts/macbook/homebrew.nix");
  assert.match(brew, /"ahkohd\/oyo\/oy"/);
  assert.match(brew, /trustedtaps = names config\.homebrew\.taps/);
  assert.match(brew, /trustedformulae = qualified config\.homebrew\.brews/);
  assert.match(read("./AGENTS.md"), /oyo-review/);
  assert.match(
    read("./AGENTS.md"),
    /pending or active review.*user says done/i,
  );
  assert.match(read("./AGENTS.md"), /Children execute one-shot tasks/);
  assert.doesNotMatch(prompt("worker"), /oyo|walkthrough/i);
});

test("ready child reviews open automatically and retain the integration gate", () => {
  const skill = read("./skills/oyo-review/SKILL.md");
  const parent = read("./AGENTS.md");
  assert.match(skill, /^---\nname: oyo-review\ndescription:/);
  assert.doesNotMatch(skill, /disable-model-invocation: true/);
  assert.match(parent, /ready for human review.*oyo-review.*open/i);
  assert.match(parent, /Integration requires explicit operator approval/);
  assert.match(skill, /Wait for questions, feedback or `next`/);
  assert.doesNotMatch(
    skill,
    /offer a walkthrough|explicit skip|ask whether.*finished|ask for.*integration approval/i,
  );
  assert.match(
    skill,
    /explicit integration approval, verified integration, and user completion/i,
  );
});

test("Rex launches the resolved executable rather than relying on login PATH", () => {
  const skill = read("./skills/oyo-review/SKILL.md");
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
  const skill = read("./skills/oyo-review/SKILL.md");
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
  const skill = read("./skills/oyo-review/SKILL.md");
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
  assert.match(module, /feature-tabs = \.\/pi\/skills\/feature-tabs/);
  assert.match(
    read("./AGENTS.md"),
    /another feature.*separate tab.*feature-tabs/i,
  );
  assert.match(
    read("./AGENTS.md"),
    /feature coordinator workspace.*excluded.*user ends the feature/i,
  );
  const skill = read("./skills/feature-tabs/SKILL.md");
  assert.match(skill, /^---\nname: feature-tabs\ndescription:/);
  assert.doesNotMatch(skill, /disable-model-invocation: true/);
  assert.match(skill, /actionable.*feature brief/);
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
  assert.ok(
    skill.includes(
      'jj --config git.colocate=false workspace add --name "$workspace_name" -r @ "$feature_workspace"',
    ),
  );
  assert.match(skill, /source-relative subdirectory/);
  assert.match(skill, /own.*REX_SESSION.*REX_BLOCK.*never.*caller/i);
  assert.match(skill, /process.*capture|capture.*process/i);
  assert.match(skill, /timeout.*inspect.*retry/i);
  assert.match(skill, /keep.*workspace.*alive.*Pi or tab.*active/i);
});

test("review stays beside its feature Pi and never closes the coordinator", () => {
  const skill = read("./skills/oyo-review/SKILL.md");
  assert.match(skill, /owning feature Pi.*same tab/i);
  assert.match(skill, /never.*app focus.*another feature tab/i);
  assert.match(skill, /never.*Pi tab or feature coordinator workspace/i);
  assert.match(read("./AGENTS.md"), /only task-created child workspaces/);
});

test("integrated cleanup removes task-owned refs and revisions; pending work stays recoverable", () => {
  const parent = read("./AGENTS.md");
  const review = read("./skills/oyo-review/SKILL.md");
  const feature = read("./skills/feature-tabs/SKILL.md");
  for (const fragment of [
    "explicit integration approval",
    "verified integration",
    "user says done",
    "task-owned UI, watches, and processes",
    "exact workspace",
    "named recoverable bookmark",
    "pending, unintegrated, or failed work",
    "operator explicitly discards",
    "oyo-review for scoped JJ cleanup",
  ])
    assert.ok(parent.includes(fragment), fragment);
  for (const fragment of [
    "remove task-created local temporary review bookmarks",
    "even when squash moved their targets onto source",
    "redundant task-owned revisions",
    "empty successors",
    "superseded trials",
    "exact workspace directory",
    "record task ownership, exact bookmark/workspace names, full change IDs",
    "Scope every JJ ref/revision operation to those recorded task resources",
    "Preserve the integrated source commit and ancestors",
    "unrelated bookmarks/remotes",
    "active/shared/source workspaces",
    "pending, unintegrated, or failed work",
    "named recoverable bookmark",
    "operator explicitly discards",
    "permanent backup or review-bookmark clutter",
  ])
    assert.ok(review.includes(fragment), fragment);
  assert.match(
    review,
    /remove integrated refs and revisions only after explicit integration approval, verified integration, and user completion/i,
  );
  assert.match(
    review,
    /pending, unintegrated, or failed work, retain a named recoverable bookmark/i,
  );
  assert.match(
    review,
    /After user completion.*forget only the exact task workspace and remove its exact directory/i,
  );
  assert.match(review, /Preserve the pending or failed revision and bookmark/i);
  assert.doesNotMatch(review, /Preserve\/update the named JJ bookmark/);
  assert.match(
    feature,
    /Pi and tab to exit.*independently verify termination/i,
  );
  assert.match(feature, /after verified integration/i);
  assert.match(feature, /preserve.*pending|pending.*preserve/i);
});

test("feature startup recovery reuses its workspace and reports recovery IDs", () => {
  const skill = read("./skills/feature-tabs/SKILL.md");
  assert.match(skill, /retry.*same already-created feature workspace/i);
  assert.match(
    skill,
    /failure report.*workspace path\/name.*session\/tab\/block IDs/i,
  );
});

test("feature launch requires an actionable request and executable Pi", () => {
  const skill = read("./skills/feature-tabs/SKILL.md");
  assert.match(
    skill,
    /Launch only for an actionable user feature request, not a request to configure this workflow/,
  );
  assert.ok(skill.includes('test -x "$pi_bin"'));
});

test("coordinator teardown waits for user exit and verification elsewhere", () => {
  const skill = read("./skills/feature-tabs/SKILL.md");
  assert.match(skill, /user explicitly ends the feature/);
  assert.match(skill, /Pi and tab to exit/i);
  assert.match(
    skill,
    /another session to independently verify termination before teardown/i,
  );
  assert.match(skill, /never remove.*live coordinator cwd/i);
});

test("worker working-copy contract keeps child review target at @", () => {
  assert.match(prompt("worker"), /Keep changes in the working-copy change/);
  const skill = read("./skills/oyo-review/SKILL.md");
  assert.match(skill, /Use `@` for this child-only diff/);
  assert.ok(
    skill.includes('"$oy_bin" control target --session "$review_session" @'),
  );
  assert.doesNotMatch(skill, /control target[^\n]*--json/);
  assert.match(skill, /sole bookmark.*stack/i);
});

test("first-party review skill needs no bridge or extra Pi package", () => {
  const module = read("../pi.nix");
  assert.match(
    module,
    /extensions = \[ "\$\{config\.home\.homeDirectory\}\/\.pi\/agent\/extensions\/command-guards\.ts" \]/,
  );
  assert.doesNotMatch(
    module,
    /pi-oyo|extensions\/oyo-review|extensions\/hunk-review/,
  );
  assert.match(read("../../../flake.nix"), /home\/oyo\/config_test\.py/);
});

test("on-demand feedback preserves native roots and human resolution", () => {
  const parent = read("./AGENTS.md");
  const skill = read("./skills/oyo-review/SKILL.md");
  assert.match(parent, /on-demand Oyo.*oyo-review/i);
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
  assert.match(skill, /no automatic delivery/i);
});

test("Oyo identity is snapshot guarded without fabricated metadata", () => {
  const skill = read("./skills/oyo-review/SKILL.md");
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
  assert.match(skill, /recheck.*snapshot.*files/i);
  assert.match(skill, /\.data\.target == @/);
  assert.match(skill, /status target.*working tree/i);
  assert.match(skill, /not by requiring equality with control/i);
  assert.match(skill, /reviewKey.*short.*change.*prefix/i);
  assert.match(skill, /mutations.*print text, not JSON/i);
  assert.match(skill, /printed `seq` if available, otherwise verify/i);
  assert.match(skill, /intended cursor.*target plus loaded patch/i);
  assert.match(skill, /inReplyTo/);
  assert.match(skill, /loaded patch.*jj diff --git -r @/i);
});
