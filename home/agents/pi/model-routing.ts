import { randomUUID } from "node:crypto";
import {
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type {
  ExtensionAPI,
  ExtensionContext,
  ModelRouteRequest,
} from "@earendil-works/pi-coding-agent";

type Mode = "mixed" | "openai" | "claude";
type Provider = "openai-codex" | "anthropic";
type Tier = "main" | "scout" | "worker" | "reviewer" | "oracle";
const providers: Provider[] = ["openai-codex", "anthropic"];
const tiers: Tier[] = ["main", "scout", "worker", "reviewer", "oracle"];
const models: Record<Provider, Record<Tier, string>> = {
  "openai-codex": {
    main: "gpt-6.1-sol",
    scout: "gpt-6-luna",
    worker: "gpt-6.1-sol",
    reviewer: "gpt-6.1-sol",
    oracle: "gpt-6-astra",
  },
  anthropic: {
    main: "claude-opus-5-5",
    scout: "claude-haiku-5-5",
    worker: "claude-sonnet-5-5",
    reviewer: "claude-opus-5-5",
    oracle: "claude-opus-5-5",
  },
};

function readJson(path: string): unknown {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
    throw error;
  }
}

function writeJson(directory: string, name: string, value: unknown) {
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const temporary = join(directory, `.${randomUUID()}.tmp`);
  try {
    writeFileSync(temporary, JSON.stringify(value), { mode: 0o600 });
    renameSync(temporary, join(directory, name));
  } finally {
    rmSync(temporary, { force: true });
  }
}

function isLimit(error: string): boolean {
  return /\b429\b|rate[ _-]?limit|too many requests|usage[ _-]?limit|insufficient_quota|quota (?:exceeded|exhausted)|exceeded.{0,30}quota|out of (?:budget|credits)|credit balance.*(?:low|exhausted)|subscription_sharing_.*usage_limit/i.test(
    error,
  );
}

function cooldown(error: string): number {
  const minutes = error.match(/try again in\s*~?\s*(\d+)\s*min/i);
  if (minutes) return Math.max(60_000, Number(minutes[1]) * 60_000);
  return /usage|quota|budget|credit/i.test(error) ? 60 * 60_000 : 5 * 60_000;
}

export default function (
  pi: ExtensionAPI,
  options: { directory?: string; now?: () => number } = {},
) {
  const directory =
    options.directory ??
    join(
      process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent"),
      "model-routing",
    );
  const now = options.now ?? Date.now;
  let recovery: { entryId: string } | undefined;

  function mode(): Mode {
    const value = readJson(join(directory, "mode.json")) ?? "mixed";
    if (value !== "mixed" && value !== "openai" && value !== "claude") {
      throw new Error("Invalid model-routing mode; use /agent-tier mixed");
    }
    return value;
  }

  function blockedUntil(provider: Provider): number {
    const value = readJson(join(directory, `${provider}.json`)) ?? 0;
    if (typeof value !== "number" || !Number.isFinite(value)) {
      throw new Error("Invalid model-routing cooldown; use /agent-tier reset");
    }
    return value;
  }

  function choose(tier: Tier, ctx: ExtensionContext) {
    const selected = mode();
    const preferred: Provider =
      tier === "reviewer" ? "anthropic" : "openai-codex";
    const order: Provider[] =
      selected === "mixed"
        ? [preferred, ...providers.filter((provider) => provider !== preferred)]
        : [selected === "openai" ? "openai-codex" : "anthropic"];
    const available = ctx.modelRegistry.getAvailable();
    for (const provider of order) {
      if (blockedUntil(provider) > now()) continue;
      const model = available.find(
        (m) => m.provider === provider && m.id === models[provider][tier],
      );
      if (model) return model;
    }
    throw new Error(
      `No available provider for ${tier} (${selected}); check /agent-tier status`,
    );
  }

  for (const tier of tiers) {
    pi.registerVirtualModel({
      provider: "tiered",
      id: tier,
      name: `Tiered ${tier}`,
      thinkingLevels: [
        "off",
        "minimal",
        "low",
        "medium",
        "high",
        "xhigh",
        "max",
      ],
      contextWindow: 1_000_000,
      maxTokens: 128_000,
      route(request: ModelRouteRequest, ctx) {
        const failed = request.failed?.message;
        if (
          request.reason === "retry" &&
          failed &&
          isLimit(failed.errorMessage ?? "") &&
          failed.content.some((block) => block.type === "toolCall")
        ) {
          throw new Error(
            "Failed response contains tool calls; inspection required before continuing",
          );
        }
        return {
          model: choose(tier, ctx),
          thinkingLevel: request.thinkingLevel,
        };
      },
    });
  }

  pi.on("turn_end", (event, ctx) => {
    recovery = undefined;
    const message = event.message;
    if (
      ctx.model?.provider !== "tiered" ||
      !tiers.includes(ctx.model.id as Tier) ||
      message.role !== "assistant" ||
      message.stopReason !== "error" ||
      !providers.includes(message.provider as Provider) ||
      !isLimit(message.errorMessage ?? "")
    )
      return;

    const provider = message.provider as Provider;
    const until = Math.max(
      blockedUntil(provider),
      now() + cooldown(message.errorMessage ?? ""),
    );
    writeJson(directory, `${provider}.json`, until);
    ctx.ui.notify(
      `${provider} limited until ${new Date(until).toISOString()}`,
      "warning",
    );

    // A response containing tool calls requires inspection before another request.
    if (
      event.toolResults.length ||
      message.content.some((block) => block.type === "toolCall")
    )
      return;
    try {
      const next = choose(ctx.model.id as Tier, ctx);
      recovery = { entryId: event.messageEntryId };
      ctx.ui.notify(`Quota fallback: ${next.provider}/${next.id}`, "warning");
    } catch {
      ctx.ui.notify("No quota fallback available; routing stopped", "warning");
    }
  });

  pi.on("agent_before_settle", (event) => {
    const pending = recovery;
    recovery = undefined;
    if (!pending || event.outcome !== "error") return;
    return {
      entries: [
        ...event.entries,
        {
          type: "context_edit" as const,
          targetId: pending.entryId,
          replacement: null,
        },
      ],
      continue: true,
    };
  });

  pi.registerCommand("agent-tier", {
    description: "Model routing: mixed, openai, claude, status, reset",
    handler: async (args, ctx) => {
      const action = args.trim() || "status";
      if (action === "reset") {
        for (const provider of providers)
          rmSync(join(directory, `${provider}.json`), { force: true });
        ctx.ui.notify("Provider cooldowns cleared", "info");
        return;
      }
      if (action === "status") {
        const limits = providers.map((provider) => {
          const until = blockedUntil(provider);
          return `${provider}: ${until > now() ? `limited until ${new Date(until).toISOString()}` : "available"}`;
        });
        ctx.ui.notify([`Routing: ${mode()}`, ...limits].join("\n"), "info");
        return;
      }
      if (action !== "mixed" && action !== "openai" && action !== "claude") {
        ctx.ui.notify(
          "Usage: /agent-tier mixed|openai|claude|status|reset",
          "warning",
        );
        return;
      }
      const model = ctx.modelRegistry.find("tiered", "main");
      if (!model || !(await pi.setModel(model)))
        throw new Error("Tiered main model is unavailable");
      writeJson(directory, "mode.json", action);
      ctx.ui.notify(
        `Routing: ${action} (all tiered sessions and subagents)`,
        "info",
      );
    },
  });
}
