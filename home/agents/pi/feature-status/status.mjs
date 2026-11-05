const phases = {
  implementing: { state: "working", message: "Implementing" },
  testing: { state: "working", message: "Testing" },
  reviewing: { state: "working", message: "Independent review" },
  "review-ready": { state: "done", message: "Ready for impact review" },
  question: { state: "blocked", kind: "question", message: "Answer needed" },
  approval: {
    state: "blocked",
    kind: "permission",
    message: "Integration approval needed",
  },
  auth: { state: "blocked", kind: "auth", message: "Authentication needed" },
  failed: { state: "error", message: "Verification failed" },
  "awaiting-merge": { state: "idle", message: "Awaiting merge" },
  complete: { state: "done", message: "Feature complete" },
  clear: { state: "clear" },
};
const controls = /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/u;
const base64 = (value) => Buffer.from(value, "utf8").toString("base64");
function title(name) {
  let value = "";
  for (const character of (name || "Feature")
    .replace(new RegExp(controls, "gu"), " ")
    .trim()) {
    if (Buffer.byteLength(value + character, "utf8") > 192) break;
    value += character;
  }
  return value || "Feature";
}

export function registerFeatureStatus(
  pi,
  Type,
  io = {
    available: (ctx) =>
      ctx.mode === "tui" &&
      process.stdout.isTTY &&
      Boolean(process.env.REX_SESSION && process.env.REX_BLOCK),
    write: (value) => process.stdout.write(value),
  },
) {
  let lastReport;
  function emit(fields) {
    const report = Object.entries(fields)
      .map(([key, value]) => `${key}=${value}`)
      .join(":");
    if (report === lastReport) return false;
    io.write(`\u001b]7501;${report}\u001b\\`);
    lastReport = fields.state === "clear" ? undefined : report;
    return true;
  }
  function clear(ctx, force = false) {
    if (io.available(ctx) && (lastReport || force))
      emit({ id: "feature", state: "clear" });
  }
  pi.on("agent_start", (_event, ctx) => clear(ctx));
  for (const event of ["session_tree", "session_start", "session_shutdown"]) {
    pi.on(event, (_event, ctx) => clear(ctx, true));
  }
  pi.on("agent_settled", (event, ctx) => {
    if (event.aborted) clear(ctx);
  });
  pi.registerTool({
    name: "feature_status",
    label: "Feature status",
    description:
      "Report this feature's phase to Rex Activity using a separate status record. Only for an activated feature workflow in interactive Rex. Does not approve integration or verify notification delivery.",
    parameters: Type.Object({
      phase: Type.Union(
        Object.keys(phases).map((phase) => Type.Literal(phase)),
      ),
      message: Type.Optional(Type.String({ minLength: 1, maxLength: 512 })),
    }),
    async execute(_id, { phase, message }, _signal, _onUpdate, ctx) {
      if (!Object.hasOwn(phases, phase))
        throw new Error("Unknown feature phase");
      if (
        message !== undefined &&
        (typeof message !== "string" ||
          !message.trim() ||
          controls.test(message) ||
          Buffer.byteLength(message, "utf8") > 512)
      ) {
        throw new Error("Feature message must be one line, 1–512 UTF-8 bytes");
      }
      if (!io.available(ctx))
        throw new Error("Feature status unavailable outside interactive Rex");
      const record = phases[phase];
      const fields = { id: "feature", state: record.state };
      if (phase !== "clear") {
        fields.app = "pi";
        fields.title = base64(title(pi.getSessionName()));
        fields.msg = base64(message?.trim() || record.message);
        if (record.kind) fields.kind = record.kind;
      }
      const emitted = emit(fields);
      return {
        content: [
          {
            type: "text",
            text: `Feature status ${emitted ? "emitted" : "unchanged"}; verify Rex program_status before claiming reception. Notification delivery is controlled by Rex.`,
          },
        ],
        details: { phase, state: record.state, emitted },
      };
    },
  });
}
