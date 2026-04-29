const fs = require("fs");
const path = require("path");
const WebSocket = require("ws");
const { createProfileClient } = require("./profile");

// ---------------------------------------------------------------------------
// Persistent log
// Sidecar runs hidden via wscript.exe shim; stdout goes nowhere. Mirror every
// console.log/error to %LOCALAPPDATA%\OSPlus\sidecar.log so we can diagnose
// after the fact (zombie WS state, IPC drops, etc.) without re-launching the
// process visibly. Truncated on each start so the file doesn't grow unbounded.
// ---------------------------------------------------------------------------
const SIDECAR_LOG = path.join(process.env.LOCALAPPDATA || ".", "OSPlus", "sidecar.log");
try {
  fs.mkdirSync(path.dirname(SIDECAR_LOG), { recursive: true });
  fs.writeFileSync(SIDECAR_LOG, "");
} catch { /* best-effort; if logging fails the sidecar still runs */ }
function tee(stream, args) {
  const line = `[${new Date().toISOString()}] ` + args.map(a => typeof a === "string" ? a : JSON.stringify(a)).join(" ") + "\n";
  try { fs.appendFileSync(SIDECAR_LOG, line); } catch { /* swallow */ }
  stream.write(line);
}
const _origLog = console.log.bind(console);
const _origErr = console.error.bind(console);
console.log = (...a) => tee(process.stdout, a);
console.error = (...a) => tee(process.stderr, a);
process.on("uncaughtException", (e) => { tee(process.stderr, ["[FATAL] uncaughtException:", e && e.stack ? e.stack : String(e)]); });
process.on("unhandledRejection", (e) => { tee(process.stderr, ["[FATAL] unhandledRejection:", e && e.stack ? e.stack : String(e)]); });

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

// WS keep-alive — distinct from the file-based game heartbeat above.
// We sit behind Caddy. When the upstream Node relay restarts, Caddy doesn't
// always tear down the client-facing socket — it can hold a "zombie" upgrade
// for minutes while ws.send() succeeds locally but no frame ever reaches the
// new relay. Periodic protocol-level pings detect that state: if no pong
// returns within WS_PONG_TIMEOUT_MS, we terminate the socket and let the
// existing reconnect path bring up a fresh one.
// See docs/learnings/sidecar-ws-keepalive.md.
const WS_PING_INTERVAL_MS = 15000;
const WS_PONG_TIMEOUT_MS  = 10000;

// ---------------------------------------------------------------------------
// Ensure IPC directory and files exist
// ---------------------------------------------------------------------------

if (!fs.existsSync(IPC_DIR)) fs.mkdirSync(IPC_DIR, { recursive: true });
if (!fs.existsSync(OUTBOX)) fs.writeFileSync(OUTBOX, "");
if (!fs.existsSync(INBOX)) fs.writeFileSync(INBOX, "");

// ---------------------------------------------------------------------------
// Profile client — owns the per-install bearer token and pushes profile
// upserts to the relay's REST API. Initialized at startup so token-file
// generation failures surface in the boot log, not at first profile_upsert.
// ---------------------------------------------------------------------------

const profileClient = createProfileClient({ log: console.log, relayUrl: RELAY_URL });

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
// Latest username Lua told us about. Cached so reconnects can re-join with
// the right identity without a fresh room_change. Lua resolves it from the
// PlayerState; sidecar never invents one.
let currentUsername = null;

function joinRoom(room) {
  if (!connected || !ws || ws.readyState !== WebSocket.OPEN) return;
  if (currentRoom === room) return;
  if (currentRoom) {
    ws.send(JSON.stringify({ type: "leave", room: currentRoom }));
    console.log(`[WS] Leaving room: ${currentRoom}`);
  }
  currentRoom = room;
  ws.send(JSON.stringify({ type: "join", room, username: currentUsername }));
  console.log(`[WS] Joining room: ${room} as ${currentUsername || "(no username)"}`);
}

function leaveCurrentRoom() {
  if (!connected || !ws || ws.readyState !== WebSocket.OPEN) return;
  if (!currentRoom) return;
  ws.send(JSON.stringify({ type: "leave", room: currentRoom }));
  console.log(`[WS] Leaving room: ${currentRoom}`);
  currentRoom = null;
}

let pingTimer = null;
let pongTimeoutTimer = null;

function stopKeepalive() {
  if (pingTimer) { clearInterval(pingTimer); pingTimer = null; }
  if (pongTimeoutTimer) { clearTimeout(pongTimeoutTimer); pongTimeoutTimer = null; }
}

function startKeepalive(socket) {
  stopKeepalive();
  pingTimer = setInterval(() => {
    if (!socket || socket.readyState !== WebSocket.OPEN) return;
    try { socket.ping(); } catch { return; }
    if (pongTimeoutTimer) clearTimeout(pongTimeoutTimer);
    pongTimeoutTimer = setTimeout(() => {
      console.log(`[WS] No pong within ${WS_PONG_TIMEOUT_MS}ms, terminating zombie connection`);
      try { socket.terminate(); } catch { /* close handler will reconnect */ }
    }, WS_PONG_TIMEOUT_MS);
  }, WS_PING_INTERVAL_MS);
}

function connect() {
  console.log(`[WS] Connecting to ${RELAY_URL} ...`);
  ws = new WebSocket(RELAY_URL);

  ws.on("open", () => {
    connected = true;
    console.log(`[WS] Connected (no room yet, waiting for match)`);
    startKeepalive(ws);
    if (currentRoom) {
      ws.send(JSON.stringify({ type: "join", room: currentRoom, username: currentUsername }));
      console.log(`[WS] Re-joining room: ${currentRoom} as ${currentUsername || "(no username)"}`);
    }
  });

  ws.on("pong", () => {
    if (pongTimeoutTimer) { clearTimeout(pongTimeoutTimer); pongTimeoutTimer = null; }
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
    stopKeepalive();
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
      if (typeof msg.username === "string" && msg.username.length > 0) {
        currentUsername = msg.username;
      }
      joinRoom(msg.room);
      continue;
    }
    if (msg.type === "room_leave") {
      leaveCurrentRoom();
      continue;
    }
    if (msg.type === "profile_upsert") {
      // profile_upsert never goes over the WS — it crosses the REST
      // boundary instead. Fire-and-forget: the profile client owns its
      // own retry queue for transient HTTP failures and logs failure
      // modes in detail. We don't await so a slow scrypt call on the
      // relay can't backpressure the IPC dispatch loop.
      profileClient.handleProfileUpsert(msg).catch((err) => {
        console.error(`[PROFILE] [ERR] handleProfileUpsert threw: ${err && err.stack ? err.stack : String(err)}`);
      });
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
