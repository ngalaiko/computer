import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const automatic = new Set([
  "agent-browser",
  "diagnosing-bugs",
  "tdd",
  "code-review",
  "codebase-design",
  "writing-for-agents",
  "encore-service",
  "rex",
  "oyo-review",
  "feature-tabs",
  "pi-subagents",
]);

export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", (event) => {
    event.systemPromptOptions.skills = event.systemPromptOptions.skills.map(
      (skill) => {
        if (skill.sourceInfo?.scope !== "user") return skill;
        return {
          ...skill,
          disableModelInvocation:
            skill.disableModelInvocation || !automatic.has(skill.name),
        };
      },
    );
  });
}
