import { expect, test } from "bun:test";
import { SerialQueue } from "./queue.ts";

test("runs tasks in FIFO order after a failed task", async () => {
  const queue = new SerialQueue();
  const events: string[] = [];

  const first = queue.enqueue(async () => {
    events.push("first");
    throw new Error("expected");
  });
  const second = queue.enqueue(async () => {
    events.push("second");
  });

  await expect(first).rejects.toThrow("expected");
  await second;
  await queue.flush();
  expect(events).toEqual(["first", "second"]);
});
