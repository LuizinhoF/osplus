const fs = require("fs");
const path = require("path");
const WebSocket = require("ws");

// ---------------------------------------------------------------------------
// Config — config.json next to the exe, then CLI arg, then env var, then default
// ---------------------------------------------------------------------------

function loadConfig() {
  const candidates = [
    path.join(path.dirname(process.execPath), "config.json"),
    path.join(process.cwd(), "config.json"),
    path.join(__dirname, "config.json"),
  ];
  console.log(`[CONFIG] Searching for config.json...`);
  for (const p of candidates) {
    console.log(`[CONFIG]   Trying: ${p}`);
    try {
      let raw = fs.readFileSync(p, "utf8");
      if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
      const cfg = JSON.parse(raw);
      console.log(`[CONFIG]   FOUND! relay_url = ${cfg.relay_url || "(not set)"}`);
      return cfg;
    } catch (err) {
      console.log(`[CONFIG]   Failed: ${err.message}`);
    }
  }
  console.log(`[CONFIG]   Not found in any location, using defaults`);
  return {};
}

const CONFIG = loadConfig();
const RELAY_URL = CONFIG.relay_url || process.argv[2] || process.env.RELAY_URL || "ws://localhost:3000";
const IPC_DIR = path.join(process.env.LOCALAPPDATA || ".", "OSPlus");
const OUTBOX = path.join(IPC_DIR, "outbox.jsonl");
const INBOX = path.join(IPC_DIR, "inbox.jsonl");
const HEARTBEAT = path.join(IPC_DIR, "heartbeat.txt");

const RECONNECT_DELAY_MS = 3000;
const HEARTBEAT_CHECK_MS = 5000;   // poll heartbeat every 5s
const HEARTBEAT_TIMEOUT_MS = 20000; // exit if no heartbeat in 20s
const HEARTBEAT_GRACE_MS = 30000;  // grace period at startup before enforcing

// ---------------------------------------------------------------------------
// Ensure IPC directory and files exist
// ---------------------------------------------------------------------------

if (!fs.existsSync(IPC_DIR)) fs.mkdirSync(IPC_DIR, { recursive: true });
if (!fs.existsSync(OUTBOX)) fs.writeFileSync(OUTBOX, "");
if (!fs.existsSync(INBOX)) fs.writeFileSync(INBOX, "");

// ---------------------------------------------------------------------------
// Outbox tracking — read offset so we only process new lines
// ---------------------------------------------------------------------------

let outboxOffset = 0;

function resetOutboxOffset() {
  try {
    outboxOffset = fs.statSync(OUTBOX).size;
  } catch {
    outboxOffset = 0;
  }
}

function readNewOutboxLines() {
  let stat;
  try {
    stat = fs.statSync(OUTBOX);
  } catch {
    return [];
  }

  if (stat.size < outboxOffset) {
    outboxOffset = 0;
  }
  if (stat.size === outboxOffset) return [];

  const fd = fs.openSync(OUTBOX, "r");
  const buf = Buffer.alloc(stat.size - outboxOffset);
  fs.readSync(fd, buf, 0, buf.length, outboxOffset);
  fs.closeSync(fd);
  outboxOffset = stat.size;

  return buf
    .toString("utf8")
    .split("\n")
    .filter((l) => l.trim().length > 0);
}

// ---------------------------------------------------------------------------
// Inbox writer — atomic append
// ---------------------------------------------------------------------------

function appendToInbox(jsonStr) {
  try {
    fs.appendFileSync(INBOX, jsonStr + "\n");
  } catch (err) {
    console.error(`[IPC] Inbox write error: ${err.message}`);
  }
}

// ---------------------------------------------------------------------------
// WebSocket connection
// ---------------------------------------------------------------------------

let ws = null;
let connected = false;
let currentRoom = null;

function joinRoom(room) {
  if (!connected || !ws || ws.readyState !== WebSocket.OPEN) return;
  if (currentRoom === room) return;
  if (currentRoom) {
    ws.send(JSON.stringify({ type: "leave", room: currentRoom }));
    console.log(`[WS] Leaving room: ${currentRoom}`);
  }
  currentRoom = room;
  ws.send(JSON.stringify({ type: "join", room }));
  console.log(`[WS] Joining room: ${room}`);
}

function leaveCurrentRoom() {
  if (!connected || !ws || ws.readyState !== WebSocket.OPEN) return;
  if (!currentRoom) return;
  ws.send(JSON.stringify({ type: "leave", room: currentRoom }));
  console.log(`[WS] Leaving room: ${currentRoom}`);
  currentRoom = null;
}

function connect() {
  console.log(`[WS] Connecting to ${RELAY_URL} ...`);
  ws = new WebSocket(RELAY_URL);

  ws.on("open", () => {
    connected = true;
    console.log(`[WS] Connected (no room yet, waiting for match)`);
    if (currentRoom) {
      ws.send(JSON.stringify({ type: "join", room: currentRoom }));
      console.log(`[WS] Re-joining room: ${currentRoom}`);
    }
  });

  ws.on("message", (raw) => {
    const str = raw.toString();
    let msg;
    try {
      msg = JSON.parse(str);
    } catch {
      return;
    }

    if (msg.type === "joined") {
      console.log(`[WS] Joined room: ${msg.room}`);
      return;
    }
    if (msg.type === "left") {
      console.log(`[WS] Left room: ${msg.room}`);
      return;
    }
    if (msg.type === "error") {
      console.error(`[WS] Server error: ${msg.error}`);
      return;
    }

    appendToInbox(str);
    console.log(`[WS] Received: ${str.slice(0, 120)}`);
  });

  ws.on("close", () => {
    connected = false;
    console.log(`[WS] Disconnected, reconnecting in ${RECONNECT_DELAY_MS}ms...`);
    setTimeout(connect, RECONNECT_DELAY_MS);
  });

  ws.on("error", (err) => {
    console.error(`[WS] Error: ${err.message}`);
  });
}

// ---------------------------------------------------------------------------
// Outbox file watcher (built-in fs.watchFile, no dependencies)
// ---------------------------------------------------------------------------

resetOutboxOffset();

fs.watchFile(OUTBOX, { interval: 50 }, () => {
  const lines = readNewOutboxLines();
  for (const line of lines) {
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      console.log(`[IPC] Skipping invalid JSON: ${line.slice(0, 80)}`);
      continue;
    }

    if (msg.type === "room_change" && msg.room) {
      joinRoom(msg.room);
      continue;
    }
    if (msg.type === "room_leave") {
      leaveCurrentRoom();
      continue;
    }

    if (!connected || !ws || ws.readyState !== WebSocket.OPEN) {
      console.log(`[IPC] Not connected, dropping: ${line.slice(0, 80)}`);
      continue;
    }
    ws.send(line);
    console.log(`[IPC] Sent: ${line.slice(0, 120)}`);
  }
});

// ---------------------------------------------------------------------------
// Heartbeat watchdog — exit when the game stops touching heartbeat.txt
//
// The Lua mod writes the current epoch seconds to heartbeat.txt every ~5s.
// If the file's mtime falls more than HEARTBEAT_TIMEOUT_MS behind wall clock,
// the game is considered gone (clean close, crash, Alt+F4, task-kill — all
// the same to us) and we exit cleanly. A startup grace period prevents the
// race where the sidecar boots faster than Lua writes the first heartbeat.
// ---------------------------------------------------------------------------

const sidecarStartedAt = Date.now();

function checkHeartbeat() {
  let stat;
  try {
    stat = fs.statSync(HEARTBEAT);
  } catch {
    if (Date.now() - sidecarStartedAt > HEARTBEAT_GRACE_MS) {
      console.log(`[HEARTBEAT] No heartbeat file after grace period, game gone — exiting`);
      process.exit(0);
    }
    return;
  }

  const age = Date.now() - stat.mtimeMs;
  if (age > HEARTBEAT_TIMEOUT_MS) {
    console.log(`[HEARTBEAT] Stale (${Math.round(age / 1000)}s old), game gone — exiting`);
    process.exit(0);
  }
}

setInterval(checkHeartbeat, HEARTBEAT_CHECK_MS);

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

console.log(`[SIDECAR] OSPlus Sidecar`);
console.log(`[SIDECAR] Relay:  ${RELAY_URL}`);
console.log(`[SIDECAR] Room:   auto (derived from match seed + team)`);
console.log(`[SIDECAR] IPC:    ${IPC_DIR}`);
console.log(`[SIDECAR] Watchdog: ${HEARTBEAT_TIMEOUT_MS / 1000}s heartbeat timeout`);

connect();
