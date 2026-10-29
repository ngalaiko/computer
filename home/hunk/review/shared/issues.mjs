import {
  constants,
  openSync,
  closeSync,
  writeSync,
  fsyncSync,
  renameSync,
  unlinkSync,
  lstatSync,
} from "node:fs";
import { join } from "node:path";
import { createHash, randomBytes } from "node:crypto";
import {
  privateStat,
  readPrivate,
  validIdentity,
  sameIdentity,
} from "./journal.mjs";

export const MAX_ISSUES = 4096;
const MAX_NOTES = 20000;
export function semanticBody(note) {
  return JSON.stringify([
    note.summary,
    note.rationale ?? "",
    note.markup ?? "",
    note.title ?? "",
  ]);
}
const fingerprint = (note) =>
  createHash("sha256").update(semanticBody(note)).digest("hex");

export function createIssueTracker() {
  let notes = new Map(),
    roots = new Map(),
    revision = 0;
  let available = false,
    error = "Saved-note snapshot required",
    generation;
  let epoch = 0,
    blocked = false;
  const firstSeen = new Map();
  function changed() {
    if (revision === Number.MAX_SAFE_INTEGER)
      throw new Error("Issue revision exhausted");
    revision++;
  }
  function rebuild() {
    const next = new Map();
    for (const note of notes.values()) {
      if (note.source !== "user" || note.parentId !== undefined) continue;
      const old = roots.get(note.id);
      next.set(note.id, {
        ...old,
        note,
        resolved: old?.resolved ?? false,
        humans: new Map(),
      });
    }
    if (next.size > MAX_ISSUES) throw new Error("Issue root limit exceeded");
    for (const note of notes.values()) {
      if (note.source !== "user") continue;
      let parent = note;
      const seen = new Set();
      while (parent?.parentId !== undefined && !seen.has(parent.id)) {
        seen.add(parent.id);
        parent = notes.get(parent.parentId);
      }
      if (!parent || seen.has(parent.id)) continue;
      const root = next.get(parent.id);
      if (!root) continue;
      const body = fingerprint(note);
      root.humans.set(note.id, body);
      if (
        roots.has(parent.id) &&
        roots.get(parent.id).humans.get(note.id) !== body
      )
        root.resolved = false;
    }
    roots = next;
  }
  function update(run) {
    const before = JSON.stringify(state());
    try {
      run();
    } catch (cause) {
      available = false;
      blocked = true;
      error = cause.message;
    }
    if (before !== JSON.stringify(state())) changed();
  }
  function remember(note) {
    if (!firstSeen.has(note.id)) firstSeen.set(note.id, { epoch, generation });
  }
  function locationVerified(id) {
    const first = firstSeen.get(id);
    const note = roots.get(id)?.note;
    return !!(
      available &&
      first &&
      first.epoch === epoch &&
      (first.generation === generation ||
        (first.generation === undefined && first.epoch === 0)) &&
      note?.resolution === "active" &&
      note.anchor.preferred
    );
  }
  function state() {
    if (!available) return { available: false, revision, error };
    const items = [...roots].map(([id, root]) => ({
      id,
      status: root.resolved ? "resolved" : "open",
      fileKey: root.note.fileKey,
      locationVerified: locationVerified(id),
    }));
    return {
      available: true,
      revision,
      open: items.filter((item) => item.status === "open").length,
      items,
    };
  }
  return {
    state,
    locationVerified,
    invalidate() {
      // Event contexts lack snapshots; only a command can restore complete counts.
      update(() => {
        epoch++;
        generation = undefined;
        available = false;
        error = "Reload: saved-note snapshot required";
      });
    },
    observe(note, removed = false) {
      if (blocked) return;
      update(() => {
        if (!removed && !notes.has(note.id) && notes.size >= MAX_NOTES)
          throw new Error("Saved-note limit exceeded");
        if (removed) {
          notes.delete(note.id);
          firstSeen.delete(note.id);
        } else {
          remember(note);
          notes.set(note.id, note);
        }
        if (notes.size > MAX_NOTES)
          throw new Error("Saved-note limit exceeded");
        rebuild();
      });
    },
    reconcile(snapshot) {
      update(() => {
        if (!snapshot) {
          available = false;
          error = "Saved-note snapshot unavailable";
          return;
        }
        if (snapshot.notes.length > MAX_NOTES)
          throw new Error("Saved-note limit exceeded");
        if (generation !== undefined && generation !== snapshot.generation)
          epoch++;
        generation = snapshot.generation;
        notes = new Map(snapshot.notes.map((note) => [note.id, note]));
        for (const id of firstSeen.keys())
          if (!notes.has(id)) firstSeen.delete(id);
        for (const note of notes.values()) remember(note);
        rebuild();
        available = true;
        blocked = false;
        error = undefined;
      });
    },
    fail(message) {
      update(() => {
        available = false;
        blocked = true;
        error = message;
      });
    },
    toggle(id) {
      if (!available || !roots.has(id)) return false;
      roots.get(id).resolved = !roots.get(id).resolved;
      changed();
      return true;
    },
  };
}

export const MAX_ISSUE_BYTES = 1024 * 1024;
export const issuePath = (dir, identity) =>
  join(dir, `${identity.pid}-${identity.nonce}.issues.json`);
const keys = (value, required, optional = []) =>
  value &&
  typeof value === "object" &&
  !Array.isArray(value) &&
  required.every((key) => Object.hasOwn(value, key)) &&
  Object.keys(value).every(
    (key) => required.includes(key) || optional.includes(key),
  );
const text = (value, limit) =>
  typeof value === "string" &&
  value.length > 0 &&
  Buffer.byteLength(value) <= limit;
function validate(value, identity) {
  const invalid = () => {
    throw new Error("Invalid issue index schema/identity");
  };
  if (
    !keys(value, [
      "schemaVersion",
      "identity",
      "issues",
      "coveredHumanSequence",
    ]) ||
    value.schemaVersion !== 1 ||
    !Number.isSafeInteger(value.coveredHumanSequence) ||
    value.coveredHumanSequence < 0 ||
    !keys(value.identity, ["kind", "version", "workspace", "pid", "nonce"]) ||
    !sameIdentity(value.identity, identity)
  )
    invalid();
  const state = value.issues;
  if (!state || !Number.isSafeInteger(state.revision) || state.revision < 0)
    invalid();
  if (state.available === false) {
    if (
      !keys(state, ["available", "revision", "error"]) ||
      !text(state.error, 1024)
    )
      invalid();
    return state;
  }
  if (
    state.available !== true ||
    !keys(state, ["available", "revision", "open", "items"]) ||
    !Array.isArray(state.items) ||
    state.items.length > MAX_ISSUES
  )
    invalid();
  const ids = new Set();
  for (const item of state.items) {
    if (
      !keys(item, ["id", "status", "fileKey", "locationVerified"]) ||
      !text(item.id, 1024) ||
      !text(item.fileKey, 8192) ||
      !["open", "resolved"].includes(item.status) ||
      typeof item.locationVerified !== "boolean" ||
      ids.has(item.id)
    )
      invalid();
    ids.add(item.id);
  }
  if (
    state.open !== state.items.filter((item) => item.status === "open").length
  )
    invalid();
  return state;
}
export function readIssueIndex(dir, identity) {
  return readIssueSnapshot(dir, identity).issues;
}
export function readIssueSnapshot(dir, identity) {
  privateStat(lstatSync(dir), true);
  if (!validIdentity(identity)) throw new Error("Invalid issue identity");
  let data;
  try {
    data = readPrivate(issuePath(dir, identity), MAX_ISSUE_BYTES);
  } catch (error) {
    if (error.code === "ENOENT") return { issues: { available: false } };
    throw error;
  }
  let value;
  try {
    value = JSON.parse(data);
  } catch {
    throw new Error("Malformed issue index");
  }
  return {
    issues: validate(value, identity),
    coveredHumanSequence: value.coveredHumanSequence,
  };
}
export function writeIssueIndex(
  dir,
  identity,
  issues,
  coveredHumanSequence = 0,
) {
  privateStat(lstatSync(dir), true);
  const value = { schemaVersion: 1, identity, issues, coveredHumanSequence };
  validate(value, identity);
  const data = Buffer.from(JSON.stringify(value));
  if (data.length > MAX_ISSUE_BYTES)
    throw new Error("Issue index exceeds limit");
  const path = issuePath(dir, identity);
  const temp = `${path}.${randomBytes(8).toString("hex")}.tmp`;
  const fd = openSync(
    temp,
    constants.O_WRONLY |
      constants.O_CREAT |
      constants.O_EXCL |
      constants.O_NOFOLLOW,
    0o600,
  );
  try {
    try {
      let offset = 0;
      while (offset < data.length) offset += writeSync(fd, data, offset);
      fsyncSync(fd);
    } finally {
      closeSync(fd);
    }
    renameSync(temp, path);
  } finally {
    try {
      unlinkSync(temp);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
}
