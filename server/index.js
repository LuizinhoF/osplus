/**
 * OSPlus chat/ping relay
 * ----------------------
 * In-memory WebSocket relay for room-scoped message broadcast.
 * State: ephemeral (rooms vanish on process restart). No persistence by design;
 * the future profile system will live in a separate process.
 *
 * Deployment:
 *   - Bound to 127.0.0.1; reverse-proxied by Caddy on the public TLS endpoint.
 *   - systemd unit at server/deploy/osplus-relay.service.
 *   - Runs as the unprivileged `osplus` user.
 *
 * Hardening (baseline; not a substitute for real auth):
 *   - 4 KB max payload (ws-level)
 *   - 5 connections per source IP
 *   - 5 messages/sec per connection (drop on violation)
 *   - Strict message-shape validation
 *   - Room codes constrained to /^[A-Z2-9]{4}$/
 *   - Chat text: control chars stripped, capped at 500 chars
 *   - Optional shared-secret token via RELAY_TOKEN env var
 */

const http = require("http");
const { WebSocketServer } = require("ws");

// === Configuration ============================================================

const PORT          = parseInt(process.env.PORT || "3000", 10);
const HOST          = process.env.HOST || "127.0.0.1";
const RELAY_TOKEN   = process.env.RELAY_TOKEN || "";
const TRUST_PROXY   = process.env.TRUST_PROXY === "1";

// === Limits ===================================================================

const MAX_PAYLOAD_BYTES = 4 * 1024;
const MAX_CONNS_PER_IP  = 5;
const MAX_MSG_RATE      = 5;
const RATE_WINDOW_MS    = 1000;
const MAX_CHAT_LENGTH   = 500;
const ROOM_CODE_RE      = /^[A-Z2-9]{4}$/;
const VALID_TYPES       = new Set(["join", "leave", "ping", "chat"]);

// === State ====================================================================

const rooms        = new Map(); // roomCode -> Set<ws>
const connsPerIp   = new Map(); // ip -> count

// === Helpers ==================================================================

function log(msg) {
  console.log(`${new Date().toISOString()} ${msg}`);
}

function getClientIp(req) {
  if (TRUST_PROXY) {
    const xff = req.headers["x-forwarded-for"];
    if (xff) return xff.split(",")[0].trim();
  }
  return req.socket.remoteAddress || "unknown";
}

function generateRoomCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 4; i++) code += chars[Math.floor(Math.random() * chars.length)];
  return code;
}

function sanitizeChatText(s) {
  if (typeof s !== "string") return "";
  return s.replace(/[\x00-\x08\x0B-\x1F\x7F]/g, "").slice(0, MAX_CHAT_LENGTH);
}

function broadcast(room, sender, message) {
  const members = rooms.get(room);
  if (!members) return;
  const raw = JSON.stringify(message);
  for (const client of members) {
    if (client !== sender && client.readyState === 1) client.send(raw);
  }
}

function removeFromRoom(ws) {
  if (!ws._room) return;
  const members = rooms.get(ws._room);
  if (members) {
    members.delete(ws);
    if (members.size === 0) {
      rooms.delete(ws._room);
      log(`[ROOM] ${ws._room} dissolved (empty)`);
    } else {
      log(`[ROOM] ${ws._room} now has ${members.size} member(s)`);
    }
  }
  ws._room = null;
}

// === HTTP server ==============================================================

const httpServer = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      status: "ok",
      uptime_sec: Math.floor(process.uptime()),
      rooms: rooms.size,
      connections: wss.clients.size,
    }));
    return;
  }
  res.writeHead(404);
  res.end();
});

// === WS server ================================================================

const wss = new WebSocketServer({
  server: httpServer,
  maxPayload: MAX_PAYLOAD_BYTES,
  verifyClient: (info, done) => {
    if (!RELAY_TOKEN) return done(true);
    try {
      const url = new URL(info.req.url, "http://x");
      if (url.searchParams.get("t") === RELAY_TOKEN) return done(true);
    } catch { /* fall through */ }
    log(`[AUTH] reject from ${getClientIp(info.req)}: bad token`);
    done(false, 401, "Unauthorized");
  },
});

wss.on("connection", (ws, req) => {
  const ip = getClientIp(req);
  const ipCount = (connsPerIp.get(ip) || 0) + 1;
  if (ipCount > MAX_CONNS_PER_IP) {
    log(`[LIMIT] ${ip} exceeded conn cap (${ipCount})`);
    ws.close(1008, "connection cap");
    return;
  }
  connsPerIp.set(ip, ipCount);

  ws._room = null;
  ws._ip = ip;
  ws._rateCount = 0;
  ws._rateWindowStart = Date.now();

  log(`[CONN] +${ip} (total: ${wss.clients.size}, from-ip: ${ipCount})`);

  ws.on("message", (raw) => {
    const now = Date.now();
    if (now - ws._rateWindowStart > RATE_WINDOW_MS) {
      ws._rateCount = 0;
      ws._rateWindowStart = now;
    }
    ws._rateCount++;
    if (ws._rateCount > MAX_MSG_RATE) {
      log(`[LIMIT] ${ws._ip} rate exceeded`);
      ws.close(1008, "rate limit");
      return;
    }

    let msg;
    try { msg = JSON.parse(raw); }
    catch {
      ws.send(JSON.stringify({ type: "error", error: "invalid JSON" }));
      return;
    }
    if (!msg || typeof msg.type !== "string" || !VALID_TYPES.has(msg.type)) {
      ws.send(JSON.stringify({ type: "error", error: "invalid type" }));
      return;
    }

    switch (msg.type) {
      case "join": {
        removeFromRoom(ws);
        let room;
        if (msg.room) {
          room = String(msg.room).toUpperCase();
          if (!ROOM_CODE_RE.test(room)) {
            ws.send(JSON.stringify({ type: "error", error: "invalid room code" }));
            return;
          }
        } else {
          room = generateRoomCode();
        }
        if (!rooms.has(room)) rooms.set(room, new Set());
        rooms.get(room).add(ws);
        ws._room = room;
        ws.send(JSON.stringify({ type: "joined", room }));
        log(`[ROOM] ${ws._ip} joined ${room} (${rooms.get(room).size} member(s))`);
        break;
      }

      case "leave": {
        const prev = ws._room;
        removeFromRoom(ws);
        ws.send(JSON.stringify({ type: "left", room: prev }));
        break;
      }

      case "chat": {
        if (!ws._room) { ws.send(JSON.stringify({ type: "error", error: "not in a room" })); return; }
        msg.text = sanitizeChatText(msg.text);
        if (!msg.text) return;
        broadcast(ws._room, ws, msg);
        break;
      }

      case "ping": {
        if (!ws._room) { ws.send(JSON.stringify({ type: "error", error: "not in a room" })); return; }
        broadcast(ws._room, ws, msg);
        break;
      }
    }
  });

  ws.on("close", () => {
    removeFromRoom(ws);
    const remaining = (connsPerIp.get(ws._ip) || 1) - 1;
    if (remaining <= 0) connsPerIp.delete(ws._ip);
    else connsPerIp.set(ws._ip, remaining);
    log(`[CONN] -${ws._ip} (total: ${wss.clients.size})`);
  });

  ws.on("error", (err) => {
    log(`[ERR] ${ws._ip}: ${err.message}`);
  });
});

// === Lifecycle ================================================================

httpServer.listen(PORT, HOST, () => {
  log(`[RELAY] Listening on ${HOST}:${PORT}`);
  log(`[RELAY] Auth:                ${RELAY_TOKEN ? "ON (token required)" : "OFF (open)"}`);
  log(`[RELAY] Trust X-Forwarded-For: ${TRUST_PROXY ? "yes" : "no"}`);
  log(`[RELAY] Limits:              ${MAX_PAYLOAD_BYTES}B/msg, ${MAX_CONNS_PER_IP} conns/ip, ${MAX_MSG_RATE} msg/s`);
});

function shutdown(sig) {
  log(`[SHUTDOWN] ${sig} received, closing ${wss.clients.size} client(s)`);
  for (const ws of wss.clients) ws.close(1001, "server shutting down");
  httpServer.close(() => {
    log(`[SHUTDOWN] HTTP closed, exiting`);
    process.exit(0);
  });
  setTimeout(() => { log("[SHUTDOWN] hard exit"); process.exit(1); }, 5000);
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT",  () => shutdown("SIGINT"));
