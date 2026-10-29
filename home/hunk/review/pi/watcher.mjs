import { realpathSync, accessSync, constants } from "node:fs";
import { isAbsolute } from "node:path";
import {
  STATE_DIR,
  readPrivate,
  descriptorPath,
  validIdentity,
  sameIdentity,
  openJournal,
} from "../shared/journal.mjs";

export function createWatcher({
  exec,
  notify,
  schedule,
  isAlive = alive,
  stateDir = STATE_DIR,
}) {
  let epoch = 0,
    active,
    cancel;
  function stop() {
    epoch++;
    cancel?.();
    cancel = undefined;
    active = undefined;
    return { running: false };
  }
  function status() {
    return active
      ? { running: true, session: active.session, identity: active.identity }
      : { running: false };
  }
  function check(token, signal) {
    signal?.throwIfAborted();
    if (token !== epoch) throw new Error("Watch replaced or stopped");
  }
  async function cli(scope, args, signal) {
    const result = await exec(scope.hunkBin, args, {
      cwd: scope.workspace,
      signal,
      timeout: 10000,
    });
    if (result.code !== 0 || result.killed || result.truncated)
      throw new Error(
        `Hunk UI unavailable or command failed: ${result.stderr || "no complete response"}`,
      );
    return JSON.parse(result.stdout);
  }
  async function verify(scope, signal) {
    const { session } = await cli(
      scope,
      ["session", "get", scope.session, "--json"],
      signal,
    );
    if (
      session?.sessionId !== scope.session ||
      !Number.isSafeInteger(session.pid) ||
      session.pid < 1 ||
      typeof session.cwd !== "string" ||
      realpathSync(session.cwd) !== scope.workspace
    )
      throw new Error("Native Hunk session identity/workspace mismatch");
    return session;
  }
  function queue(scope, token) {
    if (token !== epoch || scope !== active) return;
    cancel = schedule(async () => {
      if (token !== epoch || scope.inflight) return;
      scope.inflight = true;
      try {
        const batch = scope.reader.read();
        if (batch.feedback.length) {
          try {
            await notify({
              kind: "feedback",
              session: scope.session,
              identity: scope.identity,
              feedback: batch.feedback,
            });
          } catch {
            return;
          }
          if (token !== epoch) return;
          for (const note of batch.feedback) scope.humans.add(note.id);
        }
        batch.accept();
        scope.closed ||= batch.closed;
        if (!batch.eof) return;
        if (!isAlive(scope.identity.pid)) {
          stop();
          return;
        }
        const descriptor = JSON.parse(
          readPrivate(descriptorPath(stateDir, scope.identity.pid), 4096),
        );
        if (!sameIdentity(descriptor, scope.identity))
          throw new Error(
            "Bridge identity changed; reverify and restart watch",
          );
        if (scope.closed)
          throw new Error(
            "Bridge ended while UI is alive; reverify and restart watch",
          );
        scope.failures = 0;
      } catch (error) {
        if (token !== epoch) return;
        if (++scope.failures >= 3) {
          stop();
          try {
            await notify({
              kind: "error",
              session: scope.session,
              error: String(error.message),
            });
          } catch {
            /* The watch is already stopped. */
          }
          return;
        }
      } finally {
        scope.inflight = false;
        queue(scope, token);
      }
    }, 500);
  }
  return {
    stop,
    status,
    async reply({ replyTo, body }, signal) {
      const scope = active,
        token = epoch;
      if (!scope)
        throw new Error("No active verified Hunk watch; UI may be closed");
      if (!scope.humans.has(replyTo))
        throw new Error("replyTo must be a watched human note");
      if (
        typeof body !== "string" ||
        !body.trim() ||
        Buffer.byteLength(body) > 64 * 1024
      )
        throw new Error("Reply body must be nonempty and at most 64 KiB UTF-8");
      const session = await verify(scope, signal);
      check(token, signal);
      if (
        session.pid !== scope.identity.pid ||
        !sameIdentity(
          JSON.parse(readPrivate(descriptorPath(stateDir, session.pid), 4096)),
          scope.identity,
        )
      )
        throw new Error("Native Hunk/bridge identity changed");
      const before = await cli(
        scope,
        [
          "session",
          "comment",
          "list",
          scope.session,
          "--type",
          "all",
          "--json",
        ],
        signal,
      );
      check(token, signal);
      if (
        !Array.isArray(before.comments) ||
        !before.comments.some(
          (note) => note.noteId === replyTo && note.source === "user",
        )
      )
        throw new Error(
          "Watched human parent is no longer in the native session",
        );
      const written = await cli(
        scope,
        [
          "session",
          "comment",
          "add",
          scope.session,
          "--reply-to",
          replyTo,
          "--summary=" + body,
          "--author",
          "Pi",
          "--json",
        ],
        signal,
      );
      check(token, signal);
      const commentId = written.result?.commentId;
      if (typeof commentId !== "string" || !commentId)
        throw new Error(
          "Unverified native write response; do not retry blindly",
        );
      const after = await cli(
        scope,
        [
          "session",
          "comment",
          "list",
          scope.session,
          "--type",
          "all",
          "--json",
        ],
        signal,
      );
      check(token, signal);
      if (
        !Array.isArray(after.comments) ||
        !after.comments.some(
          (note) =>
            note.noteId === commentId &&
            note.parentId === replyTo &&
            note.source === "agent" &&
            note.author === "Pi" &&
            note.body === body,
        )
      )
        throw new Error(
          "Native reply verification failed; write may have succeeded, do not retry blindly",
        );
      return { commentId, parentId: replyTo, source: "agent", author: "Pi" };
    },
    async start(params, signal) {
      stop();
      const token = epoch;
      if (
        !isAbsolute(params.workspace || "") ||
        !isAbsolute(params.hunkBin || "") ||
        !/^[A-Za-z0-9][A-Za-z0-9._~-]{0,127}$/.test(params.session || "")
      )
        throw new Error(
          "start requires absolute workspace/hunkBin and exact native session ID",
        );
      accessSync(params.hunkBin, constants.X_OK);
      const scope = {
        ...params,
        workspace: realpathSync(params.workspace),
        humans: new Set(),
        failures: 0,
      };
      check(token, signal);
      const session = await verify(scope, signal);
      check(token, signal);
      const identity = JSON.parse(
        readPrivate(descriptorPath(stateDir, session.pid), 4096),
      );
      if (
        !validIdentity(identity) ||
        identity.pid !== session.pid ||
        identity.workspace !== scope.workspace
      )
        throw new Error("Bridge descriptor identity/workspace mismatch");
      scope.identity = identity;
      scope.reader = openJournal(stateDir, identity);
      const batch = scope.reader.read();
      check(token, signal);
      for (const note of batch.feedback) scope.humans.add(note.id);
      batch.accept();
      active = scope;
      scope.closed = batch.closed;
      if (batch.closed && batch.eof && !isAlive(identity.pid)) stop();
      else queue(scope, token);
      return { ...status(), feedback: batch.feedback, more: !batch.eof };
    },
  };
}
function alive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code !== "ESRCH";
  }
}
