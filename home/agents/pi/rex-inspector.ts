import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type {
  InspectorPlugin,
  InspectorRegistration,
  InspectorRegistrationRequest,
} from "pi-subagents/inspectors";

export default function (pi: ExtensionAPI) {
  let registration: InspectorRegistration | undefined;
  const plugin: InspectorPlugin = {
    name: "rex",
    available: ({ env }) => Boolean(env.REX_SESSION && env.REX_BLOCK),
    owns: () => false,
    async open({ cwd, env, target }, launch, params) {
      if (!env.REX_SESSION || !env.REX_BLOCK) {
        throw new Error("Rex session and pane are unavailable.");
      }
      const result = await pi.exec(
        "rex",
        [
          "split",
          "-s",
          env.REX_SESSION,
          "-b",
          env.REX_BLOCK,
          "--split=right",
          `--focus=${params.focus === true}`,
          "--shell=none",
          "--label",
          "Subagent inspector",
          "-c",
          target.status.cwd ?? cwd,
          "--json",
          "--",
          launch.executable,
          ...launch.argv,
        ],
        { cwd, timeout: 15000 },
      );
      if (result.code !== 0) {
        throw new Error(
          `Rex inspector failed: ${result.stderr.trim() || result.stdout.trim() || `exit ${result.code}`}`,
        );
      }
      return {
        content: [{ type: "text", text: "Opened subagent inspector in Rex." }],
        details: { mode: "single", results: [] },
      };
    },
  };

  pi.on("session_start", () => {
    registration?.dispose();
    registration = undefined;
    if (!process.env.REX_SESSION || !process.env.REX_BLOCK) return;
    const request: InspectorRegistrationRequest = { version: 1, plugin };
    pi.events.emit("pi-subagents:inspector-register:v1", request);
    if (!request.result) {
      throw new Error("pi-subagents inspector registration is unavailable.");
    }
    if (!request.result.ok) throw request.result.error;
    registration = request.result.registration;
  });
  pi.on("session_shutdown", () => {
    registration?.dispose();
    registration = undefined;
  });
}
