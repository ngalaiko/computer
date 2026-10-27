import { spawn, execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdir, realpath, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import type { Usage } from "@earendil-works/pi-ai";
import type {
  ExtensionAPI,
  ToolDefinition,
} from "@earendil-works/pi-coding-agent";

const exec = promisify(execFile);
const roles = {
  worker: { model: "openai-codex/gpt-6.1-sol", thinking: "medium" },
  "small-worker": { model: "openai-codex/gpt-6.1-terra", thinking: "medium" },
  reviewer: { model: "claude-code-cli/opus", thinking: "high" },
};

type Params = { task: string; role?: keyof typeof roles; cwd?: string };
type Invocation = { command: string; args: string[] };
type Details = {
  role: string;
  model: string;
  workspace?: string;
  workspaceName?: string;
  changeId?: string;
  sessionDirectory: string;
  resultPath: string;
  output: string;
};

async function jj(cwd: string, args: string[]) {
  const { stdout } = await exec(
    "jj",
    ["--color", "never", "--no-pager", ...args],
    {
      cwd,
      timeout: 60_000,
      maxBuffer: 16 * 1024 * 1024,
    },
  );
  return stdout.trim();
}

function report(text: string, path: string) {
  return text.length > 16_000
    ? `${text.slice(0, 16_000)}\n\nFull result: ${path}`
    : text;
}

function piInvocation(): Invocation {
  const script = process.argv[1];
  if (
    script &&
    /(?:^|\/)pi(?:-coding-agent)?\/(?:dist\/)?(?:cli|index)\.js$/.test(script)
  ) {
    return { command: process.execPath, args: [script] };
  }
  return { command: "pi", args: [] };
}

async function runChild(
  invocation: Invocation,
  args: string[],
  cwd: string,
  signal?: AbortSignal,
) {
  signal?.throwIfAborted();
  let output = "";
  let error = "";
  let stopReason = "";
  const usage: Usage = {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: 0,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
  };
  const child = spawn(invocation.command, [...invocation.args, ...args], {
    cwd,
    shell: false,
    detached: true,
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, PI_JJ_DELEGATE_CHILD: "1" },
  });
  const lines = createInterface({ input: child.stdout });
  lines.on("line", (line) => {
    let event;
    try {
      event = JSON.parse(line);
    } catch {
      return;
    }
    if (event.type !== "message_end" || event.message?.role !== "assistant")
      return;
    const message = event.message;
    output = message.content
      .filter((part: { type: string }) => part.type === "text")
      .map((part: { text: string }) => part.text)
      .join("\n");
    stopReason = message.stopReason;
    error = message.errorMessage ?? "";
    if (message.usage) {
      for (const key of [
        "input",
        "output",
        "cacheRead",
        "cacheWrite",
        "totalTokens",
      ] as const) {
        usage[key] += message.usage[key] ?? 0;
      }
      for (const key of [
        "input",
        "output",
        "cacheRead",
        "cacheWrite",
        "total",
      ] as const) {
        usage.cost[key] += message.usage.cost?.[key] ?? 0;
      }
    }
  });
  let stderr = "";
  child.stderr.on("data", (chunk) => {
    stderr = (stderr + chunk).slice(-16_000);
  });
  const kill = (name: NodeJS.Signals) => {
    if (!child.pid) return;
    try {
      process.kill(-child.pid, name);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ESRCH") throw error;
    }
  };
  let timer: ReturnType<typeof setTimeout> | undefined;
  const abort = () => {
    kill("SIGTERM");
    timer = setTimeout(() => kill("SIGKILL"), 1000);
  };
  signal?.addEventListener("abort", abort, { once: true });
  if (signal?.aborted) abort();
  try {
    const code = await new Promise<number | null>((resolve, reject) => {
      child.once("error", reject);
      child.once("close", resolve);
    });
    return {
      output,
      usage,
      error: signal?.aborted
        ? "Cancelled"
        : code !== 0 || stopReason !== "stop"
          ? error ||
            stderr ||
            `Child exited without a completed response (${code})`
          : undefined,
    };
  } finally {
    signal?.removeEventListener("abort", abort);
    clearTimeout(timer);
    if (signal?.aborted) kill("SIGKILL");
    lines.close();
  }
}

export default function delegate(
  pi: ExtensionAPI,
  options: { directory?: string; invocation?: Invocation } = {},
) {
  if (process.env.PI_JJ_DELEGATE_CHILD === "1") return;
  const directory =
    options.directory ?? join(homedir(), ".pi", "agent", "delegations");
  const active = new Map<AbortController, Promise<void>>();
  const workspaces = new Set<string>();
  let stopped = false;
  pi.on("session_shutdown", async () => {
    stopped = true;
    const running = [...active];
    for (const [controller] of running) controller.abort();
    await Promise.all(running.map(([, settled]) => settled));
  });
  pi.registerTool({
    name: "delegate",
    label: "Delegate",
    description:
      "Delegate a bounded task: worker (Sol medium), small-worker (Terra medium), or reviewer (Opus high, read-only). Writers get automatic JJ workspaces. Waits for completion; returns retained work and test results. At most two delegates per session.",
    promptSnippet:
      "Run a bounded task in a fresh session; writers use isolated JJ workspaces.",
    promptGuidelines: [
      "Decide when to delegate without asking. Use worker for independent implementation, small-worker for bounded changes, and reviewer for substantive review. Work directly when delegation adds overhead. Supply relevant paths, requirements, and acceptance criteria.",
      "Review a worker by passing its workspace as reviewer cwd. Integration and workspace deletion require explicit operator approval.",
    ],
    parameters: {
      type: "object",
      properties: {
        task: { type: "string", minLength: 1 },
        role: { type: "string", enum: Object.keys(roles), default: "worker" },
        cwd: {
          type: "string",
          description: "Source directory; defaults to the current directory.",
        },
      },
      required: ["task"],
      additionalProperties: false,
    } as ToolDefinition["parameters"],
    executionMode: "parallel",
    async execute(_id, params: Params, signal, onUpdate, ctx) {
      signal?.throwIfAborted();
      const role = params.role ?? "worker";
      if (!Object.hasOwn(roles, role))
        throw new Error(`Unknown delegation role: ${role}`);
      if (!params.task.trim()) throw new Error("Task must not be empty");
      if (stopped) throw new Error("Delegation session has shut down");
      if (active.size >= 2)
        throw new Error("At most two delegates may run concurrently");
      const controller = new AbortController();
      const abort = () => controller.abort();
      signal?.addEventListener("abort", abort, { once: true });
      let release!: () => void;
      active.set(
        controller,
        new Promise<void>((resolve) => {
          release = resolve;
        }),
      );
      try {
        const profile = roles[role];
        const run = join(directory, `${role}-${randomUUID()}`);
        await mkdir(run, { recursive: true, mode: 0o700 });
        const source = await realpath(resolve(ctx.cwd, params.cwd ?? "."));
        const details: Details = {
          role,
          model: profile.model,
          sessionDirectory: join(run, "sessions"),
          resultPath: join(run, "result.md"),
          output: "",
        };
        let usage: Usage | undefined;
        try {
          const root = await realpath(await jj(source, ["root"]));
          const parentRoot = await jj(ctx.cwd, ["root"]).catch(() => "");
          const trusted =
            ctx.isProjectTrusted() &&
            (root === parentRoot || workspaces.has(root));
          const review = role === "reviewer";
          if (!review) {
            details.workspaceName = `pi-${randomUUID()}`;
            details.workspace = join(run, "workspace");
            await jj(source, [
              "--config",
              "git.colocate=false",
              "workspace",
              "add",
              "--name",
              details.workspaceName,
              "-r",
              "@",
              details.workspace,
            ]);
            if (trusted) workspaces.add(await realpath(details.workspace));
          }
          const taskPath = join(run, "task.md");
          const promptPath = join(run, "instructions.md");
          await writeFile(taskPath, params.task, { mode: 0o600 });
          let instructions =
            "Work directly without delegating or launching agents. Complete the assigned task and run relevant tests. Keep changes in the working-copy change. The parent owns JJ integration and workspace cleanup. Report changed files, tests, and unresolved issues.";
          if (review) {
            const diff = join(run, "diff.patch");
            await writeFile(diff, await jj(source, ["diff", "--git"]), {
              mode: 0o600,
            });
            instructions = `Review the requirements, source files, and current-change diff at ${diff}. Report concrete bugs and missing tests with file and line references. Treat implementation claims as unverified. Use read-only tools; report test commands for the parent to run.`;
          }
          await writeFile(promptPath, instructions, { mode: 0o600 });
          const args = [
            "--mode",
            "json",
            "--print",
            "--offline",
            "--no-extensions",
            "--no-mcp",
            "--extension",
            join(dirname(fileURLToPath(import.meta.url)), "command-guards.ts"),
            ...(review
              ? [
                  "--extension",
                  join(homedir(), ".pi", "agent", "npm", "node_modules", "claude-code-pi"),
                ]
              : []),
            "--model",
            profile.model,
            "--thinking",
            profile.thinking,
            "--tools",
            review ? "read,grep,find,ls" : "read,bash,edit,write",
            "--session-dir",
            details.sessionDirectory,
            "--append-system-prompt",
            promptPath,
            trusted ? "--approve" : "--no-approve",
            "--",
            `@${taskPath}`,
          ];
          onUpdate?.({
            content: [
              {
                type: "text",
                text: `${role}: ${profile.model}\nDirectory: ${details.workspace ?? source}`,
              },
            ],
            details,
          });
          const result = await runChild(
            options.invocation ?? piInvocation(),
            args,
            details.workspace
              ? join(details.workspace, relative(root, source))
              : source,
            controller.signal,
          );
          details.output = result.output;
          usage = result.usage;
          details.changeId = await jj(details.workspace ?? source, [
            "log",
            "--no-graph",
            "-r",
            "@",
            "-T",
            "change_id",
          ]);
          if (result.error) throw new Error(result.error);
          const text = `${role}: completed\nDirectory: ${details.workspace ?? source}\nChange: ${details.changeId}\nSessions: ${details.sessionDirectory}\n\n${details.output}`;
          await writeFile(details.resultPath, text, { mode: 0o600 });
          return {
            content: [{ type: "text", text: report(text, details.resultPath) }],
            details,
            usage: result.usage,
          };
        } catch (error) {
          const text = `${role}: failed: ${error instanceof Error ? error.message : error}\nWorkspace: ${details.workspace ?? "none"}\nChange: ${details.changeId ?? "unknown"}\nSessions: ${details.sessionDirectory}\n\n${details.output}`;
          await writeFile(details.resultPath, text, { mode: 0o600 });
          return {
            isError: true,
            content: [{ type: "text", text: report(text, details.resultPath) }],
            details,
            usage,
          };
        }
      } finally {
        signal?.removeEventListener("abort", abort);
        active.delete(controller);
        release();
      }
    },
  });
}
