import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const separator = "(?:^|[;&|(`\\n])\\s*";
const flags = "(?:-[^\\s]+\\s+(?:[^-][^\\s]*\\s+)?)*";
const git = new RegExp(`${separator}git(?:\\s|$)`);
const push = new RegExp(
  `${separator}jj\\s+${flags}git\\s+${flags}push(?:\\s|$)`,
);

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event) => {
    if (event.toolName !== "bash") return;
    const command = event.input.command as string;
    if (git.test(command)) {
      return { block: true, reason: "Use jujutsu (jj), never git." };
    }
    if (push.test(command)) {
      return { block: true, reason: "Never push to remote." };
    }
  });
}
