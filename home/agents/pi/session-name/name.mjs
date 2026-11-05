export function registerSessionName(pi, Type) {
  pi.registerTool({
    name: "set_session_name",
    label: "Session name",
    description:
      "Set this Pi conversation's display name. Use a concise task + activity name; does not rename Rex sessions or tabs.",
    parameters: Type.Object({
      name: Type.String({ minLength: 1, maxLength: 120 }),
    }),
    async execute(_id, { name }) {
      if (
        typeof name !== "string" ||
        !name.trim() ||
        name.length > 120 ||
        /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/u.test(name)
      ) {
        throw new Error("Session name must be 1–120 characters on one line");
      }
      name = name.trim();
      const changed = pi.getSessionName() !== name;
      if (changed) pi.setSessionName(name);
      if (pi.getSessionName() !== name) {
        throw new Error("Could not verify Pi session name");
      }
      return {
        content: [{ type: "text", text: name }],
        details: { name, changed },
      };
    },
  });
}
