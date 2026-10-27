import { readFileSync, writeFileSync } from "node:fs";

const args = process.argv.slice(2);
const option = (name) => args[args.indexOf(name) + 1];
const task = JSON.parse(readFileSync(args.at(-1).slice(1), "utf8"));
const baseContent = task.inspect
  ? readFileSync(task.inspect, "utf8")
  : undefined;
if (task.file) writeFileSync(task.file, task.content);
if (task.ready) writeFileSync(task.ready, String(process.pid));
if (task.wait)
  await new Promise(() => {
    setInterval(() => {}, 1000);
  });
if (task.exit) {
  process.stderr.write("child startup failed");
  process.exit(task.exit);
}
const nestedTools = [];
if (task.extension) {
  const { default: extension } = await import(task.extension);
  extension({ registerTool: (tool) => nestedTools.push(tool.name), on() {} });
}
const response = {
  nestedTools,
  padding: task.padding ? "x".repeat(task.padding) : undefined,
  model: option("--model"),
  thinking: option("--thinking"),
  tools: option("--tools"),
  args,
  cwd: process.cwd(),
  prompt: readFileSync(option("--append-system-prompt"), "utf8"),
  baseContent,
};
const message = {
  role: "assistant",
  model: option("--model").split("/")[1],
  provider: option("--model").split("/")[0],
  content: [{ type: "text", text: JSON.stringify(response) }],
  stopReason: task.error ? "error" : "stop",
  errorMessage: task.error,
  usage: {
    input: 10,
    output: 5,
    cacheRead: 20,
    cacheWrite: 0,
    totalTokens: 35,
    cost: {
      input: 0.01,
      output: 0.02,
      cacheRead: 0.001,
      cacheWrite: 0,
      total: 0.031,
    },
  },
};
if (task.multi) {
  process.stdout.write(
    `${JSON.stringify({ type: "message_end", message: { ...message, stopReason: "toolUse" } })}\n`,
  );
}
process.stdout.write(`${JSON.stringify({ type: "message_end", message })}\n`);
process.stdout.write(
  `${JSON.stringify({ type: "agent_end", messages: [message] })}\n`,
);
