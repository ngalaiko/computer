import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import modelRouting from "./model-routing.ts";

const sdkEntry = process.env.PI_SDK_ENTRY;

for (const [errorMessage, retry] of [
  ["You have hit your ChatGPT usage limit. Try again in ~60 min.", false],
  ["429 rate_limit_error: too many requests", true],
]) {
  test(
    `quota recovery preserves tools (automatic retry: ${retry})`,
    { skip: !sdkEntry },
    async (t) => {
      const {
        createAgentSession,
        DefaultResourceLoader,
        ModelRuntime,
        SessionManager,
        SettingsManager,
      } = await import(sdkEntry);
      const directory = mkdtempSync(join(tmpdir(), "pi-routing-sdk-"));
      t.after(() => rmSync(directory, { recursive: true, force: true }));
      const runtime = await ModelRuntime.create({
        authPath: join(directory, "auth.json"),
        modelsPath: join(directory, "models.json"),
      });
      runtime.registerProvider("openai-codex", {
        apiKey: "test",
        baseUrl: "http://127.0.0.1:1/v1",
        api: "openai-responses",
        models: [runtime.getModel("openai-codex", "gpt-6.1-sol")],
      });
      await runtime.setRuntimeApiKey("anthropic", "test");
      const settingsManager = SettingsManager.inMemory({
        compaction: { enabled: false },
        retry: { enabled: retry, baseDelayMs: 1, maxRetries: 1 },
      });
      const loader = new DefaultResourceLoader({
        cwd: directory,
        agentDir: directory,
        settingsManager,
        noExtensions: true,
        noSkills: true,
        noPromptTemplates: true,
        noThemes: true,
        extensionFactories: [
          (pi) => modelRouting(pi, { directory: join(directory, "routing") }),
        ],
      });
      await loader.reload();
      const executions = [];
      const { session } = await createAgentSession({
        cwd: directory,
        agentDir: directory,
        modelRuntime: runtime,
        model: runtime.getModel("openai-codex", "gpt-6.1-sol"),
        resourceLoader: loader,
        settingsManager,
        sessionManager: SessionManager.inMemory(directory),
        tools: ["record"],
        customTools: [
          {
            name: "record",
            label: "Record",
            description: "Record a test action",
            parameters: { type: "object", properties: {} },
            execute: async () => {
              executions.push("write");
              return {
                content: [{ type: "text", text: "written" }],
                details: undefined,
              };
            },
          },
        ],
      });
      t.after(() => session.dispose());
      await session.bindExtensions({
        onError: (error) => {
          throw new Error(JSON.stringify(error));
        },
      });
      await session.setModel(runtime.getModel("tiered", "main"));
      session.setActiveToolsByName(["record"]);
      const calls = [];
      session.agent.streamFunction = (model, context) => {
        calls.push({
          model: `${model.provider}/${model.id}`,
          messages: context.messages,
        });
        const index = calls.length;
        const message = {
          role: "assistant",
          api: model.api,
          provider: model.provider,
          model: model.id,
          timestamp: Date.now(),
          usage: {
            input: 0,
            output: 0,
            cacheRead: 0,
            cacheWrite: 0,
            totalTokens: 0,
            cost: {
              input: 0,
              output: 0,
              cacheRead: 0,
              cacheWrite: 0,
              total: 0,
            },
          },
          stopReason: index === 1 ? "toolUse" : index === 2 ? "error" : "stop",
          content:
            index === 1
              ? [
                  {
                    type: "toolCall",
                    id: "record-1",
                    name: "record",
                    arguments: {},
                  },
                ]
              : index === 2
                ? []
                : [{ type: "text", text: "done" }],
          ...(index === 2 ? { errorMessage } : {}),
        };
        return {
          async *[Symbol.asyncIterator]() {
            yield message.stopReason === "error"
              ? { type: "error", reason: "error", error: message }
              : { type: "done", reason: message.stopReason, message };
          },
          async result() {
            return message;
          },
        };
      };
      await session.prompt("Record once, then finish.");
      assert.deepEqual(
        executions,
        ["write"],
        JSON.stringify({ calls, messages: session.messages }),
      );
      assert.deepEqual(
        calls.map((call) => call.model),
        [
          "openai-codex/gpt-6.1-sol",
          "openai-codex/gpt-6.1-sol",
          "anthropic/claude-opus-5-5",
        ],
      );
      assert.equal(session.getLastAssistantText(), "done");
      assert.equal(
        calls[2].messages.some(
          (m) => m.role === "assistant" && m.stopReason === "error",
        ),
        false,
      );
      assert.equal(
        calls[2].messages.filter((m) => m.role === "toolResult").length,
        1,
      );
    },
  );
}
