import type {
  HunkExtensionAPI,
  ExtensionEventContext,
  ExtensionCommandContext,
  ExtensionReviewNote,
  ExtensionPaneComponent,
} from "hunkdiff/extension";
import {
  createIssueTracker,
  semanticBody,
  writeIssueIndex,
} from "../shared/issues.mjs";
import { createIssuesPaneController } from "./pane.mjs";
import { STATE_DIR, createJournal } from "../shared/journal.mjs";

export default function (
  hunk: HunkExtensionAPI,
  options: {
    stateDir?: string;
    renderPane?: (
      controller: ReturnType<typeof createIssuesPaneController>,
    ) => ExtensionPaneComponent;
  } = {},
) {
  if (hunk.apiVersion !== 32)
    throw new Error(
      `Pi review requires Hunk API 32; received ${hunk.apiVersion}`,
    );
  let journal: ReturnType<typeof createJournal> | undefined;
  const issues = createIssueTracker();
  let releaseIssuesMode: (() => boolean) | undefined;
  const pane = createIssuesPaneController({
    toggle(id, notify) {
      if (!issues.toggle(id)) return false;
      publish();
      pane.sync(issues.state());
      const state = issues.state();
      notify(
        state.available
          ? `${state.open} open — extension issue status`
          : state.error,
        state.available ? "info" : "warning",
      );
      hunk.events.emit("pi-review:issue-status", null);
      return state.available;
    },
    invalidate() {
      issues.invalidate();
      pane.invalidate();
      publish();
      pane.sync(issues.state());
      hunk.events.emit("pi-review:issue-status", null);
    },
    release() {
      releaseIssuesMode?.();
    },
  });
  hunk.events.on("pi-review:issue-status", (_event, ctx) => status(ctx));
  hunk.registerPane({
    id: "issues",
    title: "Issues",
    placement: "right",
    defaultOpen: true,
    width: { preferred: 40, min: 24, max: 56 },
    component: options.renderPane?.(pane) ?? (() => null),
  });
  hunk.registerKeyboardMode({
    id: "issues",
    title:
      "Issues · j/k select · Space resolve/reopen · Enter Go · Esc/Tab release",
    onEnter(ctx) {
      const modes = ctx.keyboardModes;
      releaseIssuesMode = () => modes.exitMode();
      pane.focus(true);
    },
    onExit() {
      releaseIssuesMode = undefined;
      pane.focus(false);
    },
    onKey(key, ctx) {
      if (key.ctrl || key.meta || key.option || key.shift) return "pass";
      if (key.name === "tab") return "exit";
      if (!pane.getSnapshot().focused) return "exit";
      const value = key.sequence ?? key.name;
      if (key.name === "down" || value === "j") pane.move(1);
      else if (key.name === "up" || value === "k") pane.move(-1);
      else if (key.name === "space" || value === " ") {
        pane.toggle();
        status(ctx);
      } else if (key.name === "return" || key.name === "enter") pane.go();
      else return "pass";
      return "handled";
    },
  });
  function focusIssues(
    ctx: ExtensionCommandContext,
    close = ctx.keyboardModes.isActive("issues"),
  ) {
    if (close) {
      ctx.keyboardModes.exitMode();
      ctx.panes.close("issues");
      return;
    }
    reconcile(ctx);
    ctx.panes.open("issues");
    ctx.keyboardModes.enterMode("issues");
  }
  hunk.registerCommand(
    { id: "issues-pane", title: "Focus/close Issues pane" },
    focusIssues,
  );
  let publishedRevision = -1;
  let publishedHumanSequence = -1;
  let coveredHumanSequence = 0;
  const pendingHumanSaves = new Map<number, string>();
  let reportedIssueError: string | undefined;
  let lastIssue: string | undefined;
  function publish() {
    const state = issues.state();
    if (
      !journal ||
      (state.revision === publishedRevision &&
        coveredHumanSequence === publishedHumanSequence)
    )
      return;
    try {
      writeIssueIndex(
        options.stateDir ?? STATE_DIR,
        journal.identity,
        state,
        coveredHumanSequence,
      );
    } catch (error) {
      issues.fail(
        `Issue index unavailable: ${String(error.code ?? error.message)}`,
      );
      try {
        writeIssueIndex(
          options.stateDir ?? STATE_DIR,
          journal.identity,
          issues.state(),
          coveredHumanSequence,
        );
      } catch {
        return;
      }
    }
    publishedRevision = issues.state().revision;
    publishedHumanSequence = coveredHumanSequence;
  }
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
  function status(ctx: Pick<ExtensionEventContext, "statusLine" | "notify">) {
    publish();
    const state = issues.state();
    pane.sync(state);
    if (
      !state.available &&
      state.error?.startsWith("Issue index unavailable") &&
      state.error !== reportedIssueError
    ) {
      ctx.notify(state.error, "error");
      reportedIssueError = state.error;
    } else if (state.available) reportedIssueError = undefined;
    const issueText = state.available
      ? `${state.open} open — extension issue status (,i / ,r / ,u)`
      : "extension issue status unavailable — ,i / ,r to refresh";
    if (unread.size) {
      ctx.statusLine.clear("issues");
      ctx.statusLine.set({
        id: "unread",
        priority: 10000,
        spans: [
          {
            text: `${unread.size} NEW REPLIES — ,n to read`,
            tone: "accent",
            attributes: ["bold"],
          },
          { text: ` · ${issueText}`, tone: "muted" },
        ],
      });
    } else {
      ctx.statusLine.clear("unread");
      ctx.statusLine.set({
        id: "issues",
        priority: 10000,
        spans: [{ text: issueText, tone: "muted" }],
      });
    }
  }
  function next(ctx: ExtensionCommandContext) {
    const snapshot = reconcile(ctx);
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
  function reconcile(ctx: ExtensionCommandContext) {
    const snapshot = ctx.review.snapshot();
    issues.reconcile(snapshot);
    pane.reconcile(snapshot);
    if (snapshot && issues.state().available && journal) {
      pendingHumanSaves.clear();
      coveredHumanSequence = journal.humanSequence;
    }
    status(ctx);
    return snapshot;
  }
  async function chooseIssue(ctx: ExtensionCommandContext) {
    const captured = reconcile(ctx);
    const state = issues.state();
    if (!captured || !state.available) {
      ctx.notify(state.error ?? "Issue state unavailable", "warning");
      return;
    }
    if (!state.items.length) {
      ctx.notify("No human issues");
      return;
    }
    const choices = state.items.map((item, index) => {
      const note = captured.notes.find((note) => note.id === item.id)!;
      const file = captured.files.find((file) => file.fileKey === note.fileKey);
      const label = `${file?.path ?? note.fileKey} — ${note.summary}`
        .replace(/[\x00-\x1f\x7f-\x9f]/gu, " ")
        .replace(/\s+/gu, " ")
        .trim()
        .slice(0, 160);
      return `${index + 1}. [${item.status}] ${label}`;
    });
    const selected = await ctx.dialogs.select({
      title: "Toggle extension issue status",
      options: choices,
    });
    if (selected === null) return;
    const ordinal = /^(\d+)\.\s/u.exec(selected)?.[1];
    const item =
      ordinal === undefined ? undefined : state.items[Number(ordinal) - 1];
    const current = reconcile(ctx);
    const latest = issues.state();
    if (
      !item ||
      !current ||
      !latest.available ||
      captured.generation !== current.generation ||
      captured.stateRevision !== current.stateRevision ||
      state.revision !== latest.revision ||
      !current.notes.some(
        (note) =>
          note.id === item.id &&
          semanticBody(note) ===
            semanticBody(captured.notes.find((note) => note.id === item.id)!),
      )
    ) {
      ctx.notify("Review or issue status changed; choose again", "warning");
      return;
    }
    if (!issues.toggle(item.id)) return;
    status(ctx);
    const persisted = issues.state();
    if (persisted.available)
      ctx.notify(`${persisted.open} open — extension issue status`);
  }
  function nextIssue(ctx: ExtensionCommandContext) {
    const snapshot = reconcile(ctx);
    const state = issues.state();
    if (!snapshot || !state.available) {
      ctx.notify("Issue state unavailable", "warning");
      return;
    }
    const open = state.items.filter((item) => item.status === "open");
    if (!open.length) {
      ctx.notify("No open extension issues");
      return;
    }
    const index =
      (open.findIndex((item) => item.id === lastIssue) + 1) % open.length;
    const item = open[index];
    lastIssue = item.id;
    const note = snapshot.notes.find((note) => note.id === item.id)!;
    const file = snapshot.files.find((file) => file.fileKey === note.fileKey);
    const anchor = note.anchor.preferred;
    if (
      !issues.locationVerified(item.id) ||
      !file ||
      !anchor ||
      !ctx.selection.files.some((visible) => visible.id === file.runtimeId)
    ) {
      ctx.notify(
        "Issue location unverified, hidden or invalid after reload; no jump",
        "warning",
      );
      return;
    }
    ctx.navigation.revealLine(file.runtimeId, anchor.side, anchor.line);
  }
  hunk.registerCommand(
    { id: "issues", title: "Resolve/reopen extension issue…" },
    chooseIssue,
  );
  hunk.registerCommand(
    { id: "next-issue", title: "Next open extension issue" },
    nextIssue,
  );
  hunk.registerCommand(
    { id: "next", title: "Read next NEW agent note/reply" },
    next,
  );
  let finishLeader: ((key: string | null) => void) | undefined;
  hunk.registerKeyboardMode({
    id: "leader",
    title:
      ",i: Issues · ,n: NEW · ,o: files · ,r: resolve/reopen · ,u: open issue",
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
    {
      id: "leader",
      title: "Review shortcuts (,i / ,n / ,o / ,r / ,u)",
      key: ",",
    },
    async (ctx) => {
      const issuesWasActive = ctx.keyboardModes.isActive?.("issues") ?? false;
      finishLeader?.(null);
      const pressed = new Promise<string | null>((resolve) => {
        finishLeader = resolve;
      });
      if (!ctx.keyboardModes.enterMode("leader")) {
        finishLeader?.(null);
        finishLeader = undefined;
      }
      const key = await pressed;
      if (key === "i") focusIssues(ctx, issuesWasActive);
      else if (key === "r") await chooseIssue(ctx);
      else if (key === "u") nextIssue(ctx);
      else if (key === "n") next(ctx);
      else if (key === "o") ctx.commands.execute("hunk.view.toggleFilesPane");
    },
  );
  hunk.on("startup", ({ cwd }, ctx) => {
    journal = createJournal({ workspace: cwd, ...options });
    status(ctx);
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
    const before = journal.humanSequence;
    journal.save(note);
    if (journal.humanSequence > before)
      pendingHumanSaves.set(journal.humanSequence, note.id);
  };
  hunk.on("note_created", save);
  hunk.on("note_edited", save);
  hunk.on("shutdown", () => {
    finishLeader?.(null);
    finishLeader = undefined;
    pane.unmount();
    journal?.close();
    journal = undefined;
  });
  hunk.on("session_reload", (_event, ctx) => {
    releaseIssuesMode?.();
    pane.invalidate();
    issues.invalidate();
    status(ctx);
  });
  hunk.on("note_changed", ({ kind, note }, ctx) => {
    issues.observe(note, kind === "removed");
    pane.observe(note, kind === "removed");
    if (note.source === "user" && kind !== "removed") {
      const saved = [...pendingHumanSaves].find(([, id]) => id === note.id);
      if (saved) pendingHumanSaves.delete(saved[0]);
      while (
        journal &&
        coveredHumanSequence < journal.humanSequence &&
        !pendingHumanSaves.has(coveredHumanSequence + 1)
      )
        coveredHumanSequence++;
    }
    status(ctx);
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
