import {
  constants,
  openSync,
  closeSync,
  writeSync,
  fsyncSync,
  mkdirSync,
  lstatSync,
  fstatSync,
  readSync,
  renameSync,
  realpathSync,
} from "node:fs";
import { randomBytes } from "node:crypto";
import { homedir } from "node:os";
import { join } from "node:path";

export const STATE_DIR = join(homedir(), ".local/state/hunk/pi-review");
export const MAX_RECORD = 1024 * 1024;
export const MAX_JOURNAL = 64 * MAX_RECORD;
export const BATCH_BYTES = 256 * 1024;
const fail = (message) => {
  throw new Error(message);
};
export function privateStat(stat, directory = false) {
  if (
    (directory ? !stat.isDirectory() : !stat.isFile()) ||
    stat.uid !== process.getuid() ||
    stat.mode & 0o077
  )
    fail("Unsafe bridge state permissions");
}
export function privateDir(dir) {
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  privateStat(lstatSync(dir), true);
}
export function readPrivate(path, limit) {
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = fstatSync(fd);
    privateStat(stat);
    if (stat.size > limit) fail("Bridge state exceeds limit");
    const buffer = Buffer.alloc(stat.size);
    if (readSync(fd, buffer, 0, buffer.length, 0) !== buffer.length)
      fail("Incomplete bridge state");
    return buffer.toString("utf8");
  } finally {
    closeSync(fd);
  }
}
export function validIdentity(value) {
  return (
    value?.version === 1 &&
    value.kind === "header" &&
    Number.isSafeInteger(value.pid) &&
    value.pid > 0 &&
    /^[a-f0-9]{32}$/.test(value.nonce) &&
    typeof value.workspace === "string"
  );
}
export function sameIdentity(a, b) {
  return (
    validIdentity(a) &&
    validIdentity(b) &&
    a.pid === b.pid &&
    a.nonce === b.nonce &&
    a.workspace === b.workspace
  );
}
export const journalPath = (dir, identity) =>
  join(dir, `${identity.pid}-${identity.nonce}.jsonl`);
export const descriptorPath = (dir, pid) => join(dir, `${pid}.json`);
export function createJournal({
  workspace,
  stateDir = STATE_DIR,
  pid = process.pid,
}) {
  privateDir(stateDir);
  const identity = {
    kind: "header",
    version: 1,
    workspace: realpathSync(workspace),
    pid,
    nonce: randomBytes(16).toString("hex"),
  };
  const path = journalPath(stateDir, identity);
  const fd = openSync(
    path,
    constants.O_WRONLY |
      constants.O_CREAT |
      constants.O_EXCL |
      constants.O_NOFOLLOW,
    0o600,
  );
  let size = 0,
    seq = 0,
    closed = false;
  const seen = new Map();
  function append(record) {
    const data = Buffer.from(JSON.stringify(record) + "\n");
    if (data.length > MAX_RECORD || size + data.length > MAX_JOURNAL)
      fail("Bridge journal full; feedback was not transported");
    let offset = 0;
    while (offset < data.length) offset += writeSync(fd, data, offset);
    fsyncSync(fd);
    size += data.length;
  }
  append(identity);
  const temp = `${path}.descriptor`;
  const descriptor = openSync(temp, "wx", 0o600);
  try {
    writeSync(descriptor, JSON.stringify(identity));
    fsyncSync(descriptor);
  } finally {
    closeSync(descriptor);
  }
  renameSync(temp, descriptorPath(stateDir, pid));
  return {
    identity,
    path,
    get humanSequence() {
      return seq;
    },
    save(note) {
      if (closed) fail("Bridge journal closed");
      if (note.draft) return;
      const record = {
        kind: "human",
        seq: seq + 1,
        id: note.id,
        parentId: note.parentId,
        file: note.filePath,
        line: note.line,
        side: note.side,
        body: note.body,
        oldRange: note.oldRange,
        newRange: note.newRange,
      };
      const semantic = JSON.stringify({ ...record, seq: 0 });
      if (seen.get(note.id) === semantic) return;
      append(record);
      seen.set(note.id, semantic);
      seq++;
    },
    close() {
      if (closed) return;
      try {
        append({ kind: "closed", seq: seq + 1 });
      } finally {
        closed = true;
        closeSync(fd);
      }
    },
  };
}

export function openJournal(stateDir, identity) {
  privateStat(lstatSync(stateDir), true);
  if (!validIdentity(identity)) fail("Invalid bridge identity");
  const path = journalPath(stateDir, identity);
  const header = JSON.stringify(identity) + "\n";
  let cursor = Buffer.byteLength(header),
    seq = 0,
    inode;
  function read() {
    const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
      const stat = fstatSync(fd);
      privateStat(stat);
      if (
        stat.size > MAX_JOURNAL ||
        stat.size < cursor ||
        (inode && inode !== `${stat.dev}:${stat.ino}`)
      )
        fail("Bridge journal identity/size changed");
      inode = `${stat.dev}:${stat.ino}`;
      const prefix = Buffer.alloc(Buffer.byteLength(header));
      readSync(fd, prefix, 0, prefix.length, 0);
      if (prefix.toString() !== header) fail("Bridge journal header changed");
      const buffer = Buffer.alloc(
        Math.min(stat.size - cursor, MAX_RECORD + BATCH_BYTES),
      );
      const length = readSync(fd, buffer, 0, buffer.length, cursor);
      let offset = 0,
        nextSeq = seq;
      const feedback = [];
      let closed = false;
      while (offset < length) {
        const end = buffer.indexOf(10, offset);
        if (end < 0) {
          if (feedback.length) break;
          fail("Incomplete bridge journal record");
        }
        if (end - offset + 1 > MAX_RECORD) fail("Bridge record exceeds limit");
        let record;
        try {
          record = JSON.parse(buffer.subarray(offset, end).toString("utf8"));
        } catch {
          if (feedback.length) break;
          fail("Malformed bridge journal record");
        }
        if (record.seq !== nextSeq + 1) {
          if (feedback.length) break;
          fail("Bridge journal sequence changed");
        }
        if (record.kind === "closed") {
          closed = true;
          offset = end + 1;
          nextSeq++;
          break;
        }
        if (
          record.kind !== "human" ||
          typeof record.id !== "string" ||
          !record.id ||
          typeof record.body !== "string" ||
          typeof record.file !== "string" ||
          !["old", "new"].includes(record.side) ||
          !Number.isSafeInteger(record.line) ||
          record.line < 1 ||
          (record.parentId !== undefined && typeof record.parentId !== "string")
        ) {
          if (feedback.length) break;
          fail("Invalid bridge human record");
        }
        feedback.push(record);
        offset = end + 1;
        nextSeq++;
        if (offset >= BATCH_BYTES) break;
      }
      return {
        feedback,
        closed,
        eof: cursor + offset === stat.size,
        accept() {
          cursor += offset;
          seq = nextSeq;
        },
      };
    } finally {
      closeSync(fd);
    }
  }
  return { read };
}
