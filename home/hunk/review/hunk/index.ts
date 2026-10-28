import type {
  HunkExtensionAPI,
  ExtensionEventContext,
  ExtensionCommandContext,
  ExtensionReviewSnapshotNote,
  ExtensionReviewNote,
} from "hunkdiff/extension";
import { createJournal } from "../shared/journal.mjs";

export default function (
  hunk: HunkExtensionAPI,
  options: { stateDir?: string } = {},
) {
  if (hunk.apiVersion !== 32)
    throw new Error(
      `Pi review requires Hunk API 32; received ${hunk.apiVersion}`,
    );
  let journal: ReturnType<typeof createJournal> | undefined;
  const bodies = new Map<string, string>();
  const unread = new Map<string, string>();
  let pending:
    | {
        id: string;
        body: string;
        generation: string;
        runtimeId: string;
        side: "old" | "new";
        line: number;
      }
    | undefined;
  function status(ctx: Pick<ExtensionEventContext, "statusLine">) {
    if (unread.size)
      ctx.statusLine.set({
        id: "unread",
        priority: 10000,
        spans: [
          {
            text: `${unread.size} NEW REPLIES — ,n to read`,
            tone: "accent",
            attributes: ["bold"],
          },
        ],
      });
    else ctx.statusLine.clear("unread");
  }
  function next(ctx: ExtensionCommandContext) {
    const snapshot = ctx.review.snapshot();
    if (!snapshot) {
      ctx.notify("Review unavailable; unread retained", "warning");
      return;
    }
    const ids = new Set(snapshot.notes.map((note) => note.id));
    for (const id of bodies.keys()) {
      if (!ids.has(id)) bodies.delete(id);
    }
    for (const id of unread.keys()) {
      if (!ids.has(id)) unread.delete(id);
    }
    status(ctx);
    if (pending) {
      const note = snapshot.notes.find((note) => note.id === pending!.id);
      const file = snapshot.files.find(
        (file) => file.fileKey === note?.fileKey,
      );
      if (
        snapshot.generation === pending.generation &&
        note?.resolution === "active" &&
        file?.runtimeId === pending.runtimeId &&
        note.anchor.preferred?.side === pending.side &&
        note.anchor.preferred.line === pending.line &&
        semanticBody(note) === pending.body &&
        unread.get(note.id) === pending.body &&
        ctx.selection.file?.id === pending.runtimeId &&
        ctx.selection.currentLine?.side === pending.side &&
        ctx.selection.currentLine.line === pending.line
      ) {
        unread.delete(pending.id);
        status(ctx);
      }
      pending = undefined;
    }
    if (!unread.size) {
      ctx.notify("No NEW replies");
      return;
    }
    for (const [id, body] of unread) {
      const note = snapshot.notes.find((note) => note.id === id);
      const file = snapshot.files.find(
        (file) => file.fileKey === note?.fileKey,
      );
      const anchor = note?.anchor.preferred;
      if (
        !note ||
        note.resolution !== "active" ||
        !file ||
        !anchor ||
        !ctx.selection.files.some((visible) => visible.id === file.runtimeId)
      )
        continue;
      pending = {
        id,
        body,
        generation: snapshot.generation,
        runtimeId: file.runtimeId,
        ...anchor,
      };
      ctx.navigation.revealLine(file.runtimeId, anchor.side, anchor.line);
      ctx.notify("Jump requested; ,n again confirms the landed line");
      return;
    }
    ctx.notify(
      "Unread retained: notes are hidden, stale, orphaned, or lack an active anchor",
      "warning",
    );
  }
  hunk.registerCommand(
    { id: "next", title: "Read next NEW agent note/reply" },
    next,
  );
  let finishLeader: ((key: string | null) => void) | undefined;
  hunk.registerKeyboardMode({
    id: "leader",
    title: ",n: NEW replies · ,o: files",
    onKey(key) {
      const finish = finishLeader;
      finishLeader = undefined;
      finish?.(
        !key.ctrl && !key.meta && !key.option
          ? (key.sequence ?? key.name ?? null)
          : null,
      );
      return "exit";
    },
    onExit() {
      finishLeader?.(null);
      finishLeader = undefined;
    },
  });
  hunk.registerCommand(
    { id: "leader", title: "Review shortcuts (,n / ,o)", key: "," },
    async (ctx) => {
      finishLeader?.(null);
      const pressed = new Promise<string | null>((resolve) => {
        finishLeader = resolve;
      });
      if (!ctx.keyboardModes.enterMode("leader")) {
        finishLeader?.(null);
        finishLeader = undefined;
      }
      const key = await pressed;
      if (key === "n") next(ctx);
      else if (key === "o") ctx.commands.execute("hunk.view.toggleFilesPane");
    },
  );
  hunk.on("startup", ({ cwd }, ctx) => {
    journal = createJournal({ workspace: cwd, ...options });
    ctx.statusLine.set({
      id: "bridge",
      priority: -100,
      spans: [
        {
          text: `Pi bridge ${journal.identity.pid}/${journal.identity.nonce}`,
          tone: "muted",
        },
      ],
    });
  });
  const save = ({ note }: { note: ExtensionReviewNote }) => {
    if (!journal) throw new Error("Pi review journal unavailable");
    journal.save(note);
  };
  hunk.on("note_created", save);
  hunk.on("note_edited", save);
  hunk.on("shutdown", () => {
    finishLeader?.(null);
    finishLeader = undefined;
    journal?.close();
    journal = undefined;
  });
  hunk.on("note_changed", ({ kind, note }, ctx) => {
    if (note.source !== "agent" && note.source !== "ai") return;
    if (kind === "removed") {
      unread.delete(note.id);
      bodies.delete(note.id);
      status(ctx);
      return;
    }
    const body = semanticBody(note);
    if (bodies.get(note.id) === body) return;
    bodies.set(note.id, body);
    unread.set(note.id, body);
    ctx.notify("NEW agent note/reply — ,n to read");
    status(ctx);
  });
}
function semanticBody(note: ExtensionReviewSnapshotNote) {
  return JSON.stringify([
    note.summary,
    note.rationale ?? "",
    note.markup ?? "",
    note.title ?? "",
  ]);
}
