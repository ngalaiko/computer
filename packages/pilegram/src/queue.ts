/**
 * A failure-tolerant FIFO promise queue.
 *
 * Each submitted task starts after every earlier task has settled. Individual
 * task failures are returned to their caller but never poison later work.
 */
export class SerialQueue {
  private tail: Promise<void> = Promise.resolve();

  enqueue<T>(task: () => Promise<T>): Promise<T> {
    const run = this.tail.then(task);
    this.tail = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  /** Wait for all work submitted before this call. */
  async flush(): Promise<void> {
    await this.tail;
  }
}
