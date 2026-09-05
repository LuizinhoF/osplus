const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

// Run the actual sidecar dispatcher with isolated IPC, sockets, and timers.
// No installed files, real network, background watcher, or game is involved.
function startSidecar() {
  const entry = path.resolve(__dirname, "../index.js");
  const ipcDir = path.resolve(__dirname, "isolated-presence-ipc", "OSPlus");
  const outbox = path.join(ipcDir, "outbox.jsonl");
  const inbox = path.join(ipcDir, "inbox.jsonl");
  const files = new Map();
  const sockets = [];
  const timers = [];
  const logs = [];
  let onOutboxChanged;
  class Socket extends EventEmitter {
    static OPEN = 1;
    constructor() { super(); this.readyState = 0; this.sent = []; sockets.push(this); }
    send(raw) { this.sent.push(JSON.parse(raw)); }
    ping() {}
    terminate() { this.readyState = 3; this.emit("close"); }
    open() { this.readyState = 1; this.emit("open"); }
    receive(message) { this.emit("message", Buffer.from(JSON.stringify(message))); }
  }
  const fakeFs = {
    mkdirSync() {}, existsSync: (file) => files.has(file),
    writeFileSync: (file, value) => files.set(file, String(value)),
    appendFileSync: (file, value) => files.set(file, (files.get(file) || "") + value),
    readFileSync(file) { if (!files.has(file)) throw new Error("ENOENT"); return files.get(file); },
    statSync(file) { if (!files.has(file)) throw new Error("ENOENT"); return { size: Buffer.byteLength(files.get(file)), mtimeMs: Date.now() }; },
    openSync: (file) => file,
    readSync(file, target, offset, length, position) { return Buffer.from(files.get(file)).copy(target, offset, position, position + length); },
    closeSync() {}, watchFile(_, __, callback) { onOutboxChanged = callback; },
  };
  const timer = (callback, delay) => { const handle = { callback, delay }; timers.push(handle); return handle; };
  vm.runInNewContext(fs.readFileSync(entry, "utf8"), {
    require(name) {
      if (name === "fs") return fakeFs;
      if (name === "path") return path;
      if (name === "ws") return Socket;
      if (name === "./profile") return { createProfileClient: () => ({ handleProfileUpsert: async () => {} }) };
      if (name === "./update") return { createUpdateClient: () => ({ check: async () => {}, handleUpdateCheck: async () => {} }) };
      throw new Error(`Unexpected dependency: ${name}`);
    },
    __dirname: path.dirname(entry), Buffer,
    console: { log() {}, error() {} },
    process: {
      env: { LOCALAPPDATA: path.dirname(ipcDir) }, execPath: path.join(path.dirname(ipcDir), "node.exe"),
      argv: ["node", entry], cwd: () => path.dirname(ipcDir), on() {}, exit() {},
      stdout: { write: (line) => logs.push(line) }, stderr: { write: (line) => logs.push(line) },
    },
    setInterval: timer, setTimeout: timer, clearInterval() {}, clearTimeout() {},
  }, { filename: entry });
  return {
    sockets, logs, files,
    get socket() { return sockets.at(-1); },
    get inbox() { return (files.get(inbox) || "").trim().split("\n").filter(Boolean).map(JSON.parse); },
    ipc(message) { fakeFs.appendFileSync(outbox, JSON.stringify(message) + "\n"); onOutboxChanged(); },
    reconnect() {
      this.socket.terminate();
      const pending = timers.findLast((handle) => handle.delay === 3000);
      assert.ok(pending, "sidecar queued its normal reconnect");
      pending.callback();
      this.socket.open();
    },
  };
}

const roomChange = (extra = {}) => ({
  type: "room_change", room: "PREGAME1", username: "Local", team: 0,
  spectator: false, revealOpponents: false, presenceRevision: 1, ...extra,
});
const presence = (extra = {}) => ({
  type: "presence", room: "PREGAME1", members: "Local\nAlly",
  revealOpponents: false, presenceRevision: 1, ...extra,
});

test("join and reconnect replay the latest presence context, including changes while disconnected", () => {
  const sidecar = startSidecar();
  sidecar.ipc(roomChange({ revealOpponents: true, presenceRevision: 7 }));
  assert.deepEqual(sidecar.socket.sent, []);
  sidecar.socket.open();
  assert.deepEqual(sidecar.socket.sent.at(-1), { ...roomChange({ revealOpponents: true, presenceRevision: 7 }), type: "join" });
  sidecar.ipc(roomChange({ username: "Renamed", team: 1, revealOpponents: false, presenceRevision: 8 }));
  sidecar.reconnect();
  assert.deepEqual(sidecar.socket.sent.at(-1), { ...roomChange({ username: "Renamed", team: 1, revealOpponents: false, presenceRevision: 8 }), type: "join" });
  sidecar.socket.terminate();
  sidecar.ipc(roomChange({ room: "NEXTROOM", spectator: true, team: null, revealOpponents: true, presenceRevision: 9 }));
  sidecar.reconnect();
  assert.deepEqual(sidecar.socket.sent.at(-1), { ...roomChange({ room: "NEXTROOM", spectator: true, team: null, revealOpponents: true, presenceRevision: 9 }), type: "join" });
});

test("disclosure flag is strictly boolean and invalid revisions default to zero", () => {
  for (const invalid of [undefined, null, "true", "1", 1, {}, []]) {
    const sidecar = startSidecar();
    sidecar.socket.open();
    sidecar.ipc(roomChange({ revealOpponents: invalid, presenceRevision: invalid }));
    assert.equal(sidecar.socket.sent.at(-1).revealOpponents, false);
    assert.equal(sidecar.socket.sent.at(-1).presenceRevision, invalid === 1 ? 1 : 0);
  }
  for (const revision of [-1, 0, 1.5, Number.MAX_SAFE_INTEGER + 1, "2"]) {
    const sidecar = startSidecar();
    sidecar.socket.open();
    sidecar.ipc(roomChange({ presenceRevision: revision }));
    assert.equal(sidecar.socket.sent.at(-1).presenceRevision, 0);
  }
});

test("missing, boolean, and object team values do not become confirmed teams", () => {
  for (const team of [undefined, null, false, true, {}, [], "", " ", 2]) {
    const sidecar = startSidecar();
    sidecar.socket.open();
    sidecar.ipc(roomChange({ team }));
    assert.equal(sidecar.socket.sent.at(-1).team, null);
  }
  for (const team of [0, 1, "0", "1"]) {
    const sidecar = startSidecar();
    sidecar.socket.open();
    sidecar.ipc(roomChange({ team }));
    assert.equal(sidecar.socket.sent.at(-1).team, Number(team));
  }
});

test("only presence matching current room, revision, and disclosure reaches inbox or logs", () => {
  const sidecar = startSidecar();
  sidecar.socket.open();
  sidecar.ipc(roomChange());
  const rejected = [
    presence({ room: "OTHERROOM" }), presence({ presenceRevision: 2 }),
    presence({ presenceRevision: "1" }), presence({ presenceRevision: undefined }),
    presence({ revealOpponents: true }), presence({ revealOpponents: "false" }),
    presence({ revealOpponents: undefined }),
    presence({ members: null }),
    { type: "presence", room: "PREGAME1", members: "REJECTED_SECRET" },
  ];
  for (const snapshot of rejected) {
    sidecar.socket.receive({ ...snapshot, members: snapshot.members === null ? null : "REJECTED_SECRET" });
  }
  assert.deepEqual(sidecar.inbox, []);
  assert.equal(sidecar.logs.some((line) => line.includes("REJECTED_SECRET")), false);
  sidecar.socket.receive(presence());
  assert.deepEqual(sidecar.inbox, [presence()]);
});

test("same-room context revisions and new rooms reject delayed old snapshots", () => {
  const sidecar = startSidecar();
  sidecar.socket.open();
  sidecar.ipc(roomChange({ revealOpponents: true, presenceRevision: 1 }));
  sidecar.ipc(roomChange({ team: 1, revealOpponents: false, presenceRevision: 2 }));
  sidecar.socket.receive(presence({ revealOpponents: true, members: "REJECTED_OLD_ENEMY" }));
  sidecar.socket.receive(presence({ presenceRevision: 2 }));
  assert.deepEqual(sidecar.inbox, [presence({ presenceRevision: 2 })]);
  sidecar.ipc(roomChange({ room: "NEXTROOM", presenceRevision: 3 }));
  sidecar.socket.receive(presence({ presenceRevision: 2, members: "REJECTED_OLD_ROOM" }));
  sidecar.socket.receive(presence({ room: "NEXTROOM", presenceRevision: 3, members: "Local" }));
  assert.equal(sidecar.inbox.length, 2);
  assert.equal(sidecar.logs.some((line) => line.includes("REJECTED_")), false);
});

test("leave clears disclosure context and prevents reconnect or legacy packets restoring old presence", () => {
  const sidecar = startSidecar();
  sidecar.socket.open();
  sidecar.ipc(roomChange({ revealOpponents: true, presenceRevision: 8 }));
  sidecar.ipc({ type: "room_leave" });
  sidecar.socket.receive(presence({ revealOpponents: true, presenceRevision: 8, members: "REJECTED_AFTER_LEAVE" }));
  sidecar.reconnect();
  assert.deepEqual(sidecar.socket.sent, []);
  sidecar.ipc({ type: "room_change", room: "PREGAME1", username: "Local", team: 0 });
  assert.equal(sidecar.socket.sent.at(-1).revealOpponents, false);
  assert.equal(sidecar.socket.sent.at(-1).presenceRevision, 0);
  sidecar.socket.receive({ type: "presence", room: "PREGAME1", members: "REJECTED_LEGACY" });
  assert.deepEqual(sidecar.inbox, []);
  assert.equal(sidecar.logs.some((line) => line.includes("REJECTED_")), false);
});

test("chat forwarding remains unchanged and malformed inbound data does not throw", () => {
  const sidecar = startSidecar();
  sidecar.socket.open();
  sidecar.ipc(roomChange());
  const chat = { type: "chat", text: "team", audience: "team", targetTeam: 0 };
  sidecar.ipc(chat);
  assert.deepEqual(sidecar.socket.sent.at(-1), chat);
  sidecar.socket.receive(chat);
  assert.deepEqual(sidecar.inbox, [chat]);
  assert.doesNotThrow(() => sidecar.socket.receive(null));
});
