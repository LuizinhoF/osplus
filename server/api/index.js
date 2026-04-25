/**
 * REST API dispatcher for the OSPlus relay.
 * -----------------------------------------
 * Owns the profile+auth SQLite database (`osplus.sqlite3`) and routes
 * `/api/*` requests on the relay's existing `http.Server`. Exposes:
 *
 *   handleHttp(req, res) -> boolean
 *     true  = this dispatcher handled the request (req has been responded to)
 *     false = path is not under /api/* (caller should fall through to its
 *             own routes — /health, the WS upgrade, the 404 default).
 *
 * Module boundary discipline (per ADR 0002):
 *   The DB instance is owned here; `server/index.js` only calls `handleHttp`.
 *   Reaching past this module for ad-hoc reads is grounds for a follow-up
 *   refactor.
 *
 * Body cap: 8 KB. The biggest legitimate body is a profile upsert with
 * every cosmetic field at its max; that fits in <2 KB. 8 KB leaves headroom
 * without becoming a denial-of-service amplifier.
 *
 * NOTE: Per-IP rate-limiting for /api routes is the relay's responsibility,
 * not this module's — `server/index.js` already runs Caddy in front. If
 * burst-from-internet abuse becomes real, add a small in-memory IP-bucket
 * here (the WS path's `connsPerIp` is the model).
 */

const fs = require("fs");
const path = require("path");
const Database = require("better-sqlite3");

const { applySchema } = require("./profile/schema");
const { createAuthMiddleware } = require("./middleware/auth");
const { createProfileRoutes, PID_RE } = require("./profile");

const MAX_BODY_BYTES = 8 * 1024;

function readBody(req, maxBytes) {
  return new Promise((resolve, reject) => {
    let bytes = 0;
    const chunks = [];
    let aborted = false;
    req.on("data", (chunk) => {
      if (aborted) return;
      bytes += chunk.length;
      if (bytes > maxBytes) {
        aborted = true;
        reject(Object.assign(new Error("payload too large"), { tooLarge: true }));
        try { req.destroy(); } catch { /* swallow */ }
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      if (aborted) return;
      resolve(Buffer.concat(chunks).toString("utf8"));
    });
    req.on("error", (err) => {
      if (aborted) return;
      reject(err);
    });
  });
}

function writeJson(res, status, body) {
  if (res.headersSent) return;
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(payload),
  });
  res.end(payload);
}

function createApi({ dataDir, log }) {
  fs.mkdirSync(dataDir, { recursive: true });
  const dbPath = path.join(dataDir, "osplus.sqlite3");
  const db = new Database(dbPath);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  applySchema(db);

  const auth = createAuthMiddleware({ db, log });
  const routes = createProfileRoutes({ db, log, auth });

  log(`[API] DB: ${dbPath}`);
  log(`[API] Mounted: POST /api/auth/pair, PUT|GET /api/profiles/{pid}`);

  // Returns true if this dispatcher handled the request (already responded
  // to res), false if the URL isn't /api/*.
  async function handleHttp(req, res) {
    let url;
    try { url = new URL(req.url, "http://x"); }
    catch { return false; }

    if (!url.pathname.startsWith("/api/")) return false;

    // Inside /api/*, every unmatched route returns 404 JSON instead of
    // falling through. The chat relay's /api/* namespace is exclusively
    // ours; misses are bugs (or probes), not "try the next handler."
    try {
      // POST /api/auth/pair
      if (req.method === "POST" && url.pathname === "/api/auth/pair") {
        let body;
        try { body = await readBody(req, MAX_BODY_BYTES); }
        catch (err) {
          if (err.tooLarge) return writeJson(res, 413, { error: "payload too large" });
          throw err;
        }
        await routes.handlePair(req, res, body);
        return true;
      }

      // PUT /api/profiles/{pid}
      const profileMatch = url.pathname.match(/^\/api\/profiles\/([^/]+)$/);
      if (profileMatch) {
        const pid = profileMatch[1];
        if (!PID_RE.test(pid)) {
          writeJson(res, 400, { error: "prometheusId in URL must be 24-char lowercase hex" });
          return true;
        }

        if (req.method === "PUT") {
          let body;
          try { body = await readBody(req, MAX_BODY_BYTES); }
          catch (err) {
            if (err.tooLarge) return writeJson(res, 413, { error: "payload too large" });
            throw err;
          }
          await routes.handlePut(req, res, body, pid);
          return true;
        }

        if (req.method === "GET") {
          await routes.handleGet(req, res, pid);
          return true;
        }

        writeJson(res, 405, { error: "method not allowed" });
        return true;
      }

      writeJson(res, 404, { error: "no such API route" });
      return true;
    } catch (err) {
      // Last-resort wire-boundary handler. Per node-conventions: log + drop,
      // never throw out of a handler.
      log(`[API] [ERR] ${req.method} ${url.pathname}: ${err && err.stack ? err.stack : String(err)}`);
      writeJson(res, 500, { error: "internal error" });
      return true;
    }
  }

  function close() {
    try { db.close(); } catch (err) { log(`[API] close error: ${err.message}`); }
  }

  return { handleHttp, close };
}

module.exports = { createApi };
