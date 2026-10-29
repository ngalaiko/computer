const clean = (text, limit = 160) =>
  String(text)
    .replace(/[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/gu, " ")
    .replace(/\s+/gu, " ")
    .trim()
    .slice(0, limit);

export const issueRowId = (id) => `issue-${encodeURIComponent(id)}`;

export function followIssueSelection(scroll, selectedId) {
  if (selectedId) scroll?.scrollChildIntoView(issueRowId(selectedId));
}

export function watchIssueSelection(scroll, selectedId) {
  let pending = true;
  const follow = () => {
    if (!pending || !scroll || scroll.viewport.height <= 0) return;
    pending = false;
    followIssueSelection(scroll, selectedId);
  };
  const resized = () => {
    pending = true;
    follow();
  };
  scroll?.viewport.on("layout-changed", follow);
  scroll?.viewport.on("resized", resized);
  follow();
  return () => {
    scroll?.viewport.off("layout-changed", follow);
    scroll?.viewport.off("resized", resized);
  };
}

export function createIssuesPaneController({
  toggle,
  invalidate,
  release,
} = {}) {
  let notes = new Map(),
    files = new Map(),
    generation;
  let state = { available: false, error: "Saved-note snapshot required" };
  let modelRevision = 0,
    nextOrder = 0,
    frame;
  const order = new Map(),
    listeners = new Set();
  let snapshot = Object.freeze({
    available: false,
    error: state.error,
    rows: Object.freeze([]),
    selectedId: undefined,
    focused: false,
    modelRevision,
  });
  function update(patch = {}) {
    const rows = state.available
      ? state.items
          .map((item) => {
            const note = notes.get(item.id),
              file = files.get(item.fileKey);
            if (!order.has(item.id)) order.set(item.id, nextOrder++);
            const anchor = note?.anchor.preferred;
            return Object.freeze({
              ...item,
              label: clean(
                `${file?.path ?? item.fileKey}${anchor ? `:${anchor.side}:${anchor.line}` : ":unlocated"}`,
              ),
              preview: clean(note?.summary ?? ""),
            });
          })
          .sort((a, b) => order.get(a.id) - order.get(b.id))
      : [];
    let selectedId = snapshot.selectedId;
    if (state.available && !rows.some((row) => row.id === selectedId)) {
      const previous = snapshot.rows.findIndex((row) => row.id === selectedId);
      selectedId = rows[Math.min(Math.max(0, previous), rows.length - 1)]?.id;
    }
    const next = {
      ...snapshot,
      available: state.available,
      error: state.error,
      generation,
      modelRevision,
      rows: Object.freeze(rows),
      selectedId,
      ...patch,
    };
    if (JSON.stringify(next) === JSON.stringify(snapshot)) return;
    snapshot = Object.freeze(next);
    for (const listener of listeners) listener();
  }
  function valid(captured, props) {
    return !!(
      frame &&
      frame.props === props &&
      frame.rendered === captured &&
      captured === snapshot &&
      snapshot.available &&
      generation &&
      props.reviewGeneration === generation
    );
  }
  function live(props) {
    return !!(
      frame &&
      frame.props === props &&
      snapshot.available &&
      generation &&
      props.reviewGeneration === generation
    );
  }
  function warn(message) {
    frame?.props.actions.notify(message, "warning");
    return false;
  }
  const controller = {
    getSnapshot: () => snapshot,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    sync(next) {
      state = next;
      update();
    },
    reconcile(review) {
      modelRevision++;
      generation = review?.generation;
      notes = new Map(review?.notes.map((note) => [note.id, note]) ?? []);
      files = new Map(review?.files.map((file) => [file.fileKey, file]) ?? []);
      if (review)
        for (const id of order.keys()) if (!notes.has(id)) order.delete(id);
    },
    observe(note, removed) {
      modelRevision++;
      if (removed) {
        notes.delete(note.id);
        order.delete(note.id);
      } else notes.set(note.id, note);
    },
    invalidate() {
      generation = undefined;
      modelRevision++;
    },
    focus(focused) {
      update({ focused });
    },
    frame(props, rendered) {
      const current = { props, rendered };
      frame = current;
      if (generation && props.reviewGeneration !== generation) invalidate?.();
      return () => {
        if (frame === current) frame = undefined;
      };
    },
    unmount() {
      frame = undefined;
      release?.();
      controller.focus(false);
    },
    select(id, captured, props) {
      if (
        !valid(captured, props) ||
        !snapshot.rows.some((row) => row.id === id)
      )
        return warn("Issue list changed or unavailable; ,i to refresh");
      update({ selectedId: id });
      return true;
    },
    move(delta) {
      if (!live(frame?.props))
        return warn("Issue list changed or unavailable; ,i to refresh");
      const index = snapshot.rows.findIndex(
        (row) => row.id === snapshot.selectedId,
      );
      const row =
        snapshot.rows[
          Math.min(Math.max(0, index + delta), snapshot.rows.length - 1)
        ];
      if (row) update({ selectedId: row.id });
      return true;
    },
    toggle(captured, props) {
      const explicit = arguments.length > 0;
      captured ??= snapshot;
      props ??= frame?.props;
      if (
        !(explicit ? valid(captured, props) : live(props)) ||
        !snapshot.selectedId ||
        !snapshot.rows.some((row) => row.id === snapshot.selectedId)
      )
        return warn("Issue list changed or unavailable; ,i to refresh");
      return toggle?.(snapshot.selectedId, props.actions.notify) ?? false;
    },
    go(captured, props) {
      const explicit = arguments.length > 0;
      captured ??= snapshot;
      props ??= frame?.props;
      if (!(explicit ? valid(captured, props) : live(props)))
        return warn("Issue list changed or unavailable; ,i to refresh");
      const row = snapshot.rows.find((row) => row.id === snapshot.selectedId);
      const note = notes.get(row?.id),
        file = files.get(row?.fileKey);
      const anchor = note?.anchor.preferred;
      if (
        !row?.locationVerified ||
        !anchor ||
        !file ||
        !props.files.some((visible) => visible.id === file.runtimeId)
      )
        return warn(
          "Issue location unverified, hidden or invalid after reload; no jump",
        );
      props.actions.revealLine(file.runtimeId, anchor.side, anchor.line);
      return true;
    },
  };
  return controller;
}
