import { Type } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { createWatcher } from "./watcher.mjs";

export default function (
  pi: ExtensionAPI,
  options: { stateDir?: string } = {},
) {
  const watcher = createWatcher({
    ...options,
    exec: (
      binary: string,
      args: string[],
      options: Parameters<ExtensionAPI["exec"]>[2],
    ) => pi.exec(binary, args, options),
    notify: (notice: unknown) =>
      pi.sendMessage(
        {
          customType: "hunk-watch",
          content: `Local Hunk ${(notice as { kind?: string }).kind === "issues" ? "issue status" : "review feedback"}:\n${JSON.stringify(notice)}`,
          display: true,
          details: notice,
        },
        { triggerTurn: true, deliverAs: "followUp" },
      ),
    schedule: (callback: () => Promise<void>, ms: number) => {
      const timer = setTimeout(() => {
        void callback().catch(() => watcher.stop());
      }, ms);
      return () => clearTimeout(timer);
    },
  });
  pi.on("session_shutdown", () => {
    watcher.stop();
  });
  const result = (details: unknown) => ({
    content: [{ type: "text" as const, text: JSON.stringify(details) }],
    details,
  });
  pi.registerTool({
    name: "hunk_watch",
    label: "Hunk watch",
    executionMode: "sequential",
    description:
      "Parent Pi only: explicitly start/stop/status this session’s local Hunk human-feedback watch. Verify the exact live native session first. Read initial feedback and optional extension issue state in the start result; subsequent saved feedback and issue-status changes arrive automatically. No auto-resume, remote publishing, or native-note restoration.",
    parameters: Type.Object({
      action: Type.Union([
        Type.Literal("start"),
        Type.Literal("stop"),
        Type.Literal("status"),
      ]),
      workspace: Type.Optional(
        Type.String({ description: "Absolute reviewed workspace" }),
      ),
      session: Type.Optional(
        Type.String({
          description: "Exact native Hunk session ID, not a prefix or PID",
        }),
      ),
      hunkBin: Type.Optional(
        Type.String({ description: "Absolute trusted Hunk executable" }),
      ),
    }),
    async execute(_callId, params, signal) {
      if (params.action === "start") {
        watcher.stop();
        if (!params.workspace || !params.session || !params.hunkBin)
          throw new Error("start requires workspace, session and hunkBin");
        return result(await watcher.start(params, signal));
      }
      return result(
        params.action === "stop" ? watcher.stop() : watcher.status(),
      );
    },
  });
  pi.registerTool({
    name: "hunk_reply",
    label: "Hunk reply",
    executionMode: "sequential",
    description:
      "Reply as native agent Pi to a human note delivered by this parent Pi’s active verified Hunk watch. Local native thread only; never publishes remotely. Do not retry an uncertain write blindly.",
    parameters: Type.Object({
      replyTo: Type.String({
        description: "Exact watched native human note ID",
      }),
      body: Type.String({ description: "Complete reply body" }),
    }),
    async execute(_callId, params, signal) {
      return result(await watcher.reply(params, signal));
    },
  });
}
