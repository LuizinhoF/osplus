/**
 * Sidecar profile client (per ADR 0002 + Slice 1 of in-game-profile-mvp).
 * ----------------------------------------------------------------------
 * Owns the per-install bearer token and pushes profile upserts to the
 * relay's REST API. Wired into the IPC dispatch in `sidecar/index.js` —
 * one `profile_upsert` message in, zero or one `PUT /api/profiles/{pid}`
 * out (with an auto-pair on 401).
 *
 * Token storage: `%LOCALAPPDATA%\OSPlus\token`, plain text, single line,
 * 32 random bytes base64url-encoded. The "restrictive ACL" promised by
 * ADR 0002 is provided structurally, not by `icacls`: `%LOCALAPPDATA%`
 * resolves to `C:\Users\<user>\AppData\Local\` which is per-user by
 * default — only `<user>` and `SYSTEM`/admin can read it. We do not
 * shell out to `icacls` because (a) `LOCALAPPDATA`'s default ACL is
 * already the protection we want, and (b) every extra subprocess in the
 * sidecar startup is one more thing that can fail at midnight on a
 * locked-down corporate machine.
 *
 * Auth flow per `profile_upsert`:
 *   1. PUT /api/profiles/{pid} with the supplied token.
 *   2. On 401: POST /api/auth/pair, then retry PUT once.
 *   3. On 409 from pair: maintainer-recovery situation — log + give up.
 *      Server-side comment in api/profile/index.js explains the runbook.
 *   4. On network / 5xx: cache the payload as "pending" and retry every
 *      RETRY_INTERVAL_MS until the next IPC overrides it or it succeeds.
 *
 * Idempotency: server-side PUT is idempotent (UPSERT), so the retry loop
 * is safe even if a "failed" attempt actually succeeded in flight (the
 * retry just rewrites the same row with a fresh updated_at).
 *
 * Constraint per node-conventions.mdc: Node built-ins only — no new
 * runtime deps. The SEA bundle pipeline is unchanged.
 */

const fs = require("fs");
const path = require("path");
const http = require("http");
const https = require("https");
const crypto = require("crypto");
const { URL } = require("url");

const TOKEN_FILE = path.join(process.env.LOCALAPPDATA || ".", "OSPlus", "token");
const TOKEN_BYTES = 32;
const REQUEST_TIMEOUT_MS = 10_000;
const RETRY_INTERVAL_MS = 30_000;
const MAX_PENDING_AGE_MS = 30 * 60_000; // drop a pending payload after 30 min

// 24-char lowercase hex, matches the server-side `PID_RE`.
const PID_RE = /^[0-9a-f]{24}$/;

function deriveHttpBase(wsOrHttpUrl) {
  const u = new URL(wsOrHttpUrl);
  let proto;
  if (u.protocol === "wss:") proto = "https:";
  else if (u.protocol === "ws:") proto = "http:";
  else if (u.protocol === "http:" || u.protocol === "https:") proto = u.protocol;
  else throw new Error("unsupported relay protocol: " + u.protocol);
  return `${proto}//${u.host}`;
}

function ensureToken(log) {
  fs.mkdirSync(path.dirname(TOKEN_FILE), { recursive: true });
  try {
    const existing = fs.readFileSync(TOKEN_FILE, "utf8").trim();
    if (existing.length >= 16) {
      log(`[PROFILE] Loaded existing token from ${TOKEN_FILE}`);
      return existing;
    }
    log(`[PROFILE] [!] Token file at ${TOKEN_FILE} is malformed (length ${existing.length}); regenerating`);
  } catch (err) {
    if (err.code !== "ENOENT") {
      log(`[PROFILE] [!] Token file read failed (${err.code || err.message}); regenerating`);
    }
  }
  const token = crypto.randomBytes(TOKEN_BYTES).toString("base64url");
  fs.writeFileSync(TOKEN_FILE, token, { encoding: "utf8", mode: 0o600 });
  log(`[PROFILE] Generated new token at ${TOKEN_FILE}`);
  return token;
}

// Promise-returning JSON HTTP request. Rejects only on transport error;
// HTTP 4xx/5xx resolve normally with `{status, body}` so callers can branch
// per node-conventions.mdc (log + don't throw at the wire boundary).
function jsonRequest({ baseUrl, method, pathName, headers = {}, body, log }) {
  return new Promise((resolve, reject) => {
    const url = new URL(pathName, baseUrl);
    const lib = url.protocol === "https:" ? https : http;
    const bodyStr = body == null ? null : JSON.stringify(body);
    const reqHeaders = {
      "Accept": "application/json",
      ...(bodyStr ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(bodyStr) } : {}),
      ...headers,
    };
    const req = lib.request({
      protocol: url.protocol,
      hostname: url.hostname,
      port: url.port || (url.protocol === "https:" ? 443 : 80),
      method,
      path: url.pathname + (url.search || ""),
      headers: reqHeaders,
      timeout: REQUEST_TIMEOUT_MS,
    }, (res) => {
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => {
        const raw = Buffer.concat(chunks).toString("utf8");
        let parsed = null;
        if (raw.length > 0) {
          try { parsed = JSON.parse(raw); }
          catch { parsed = { _rawText: raw.slice(0, 200) }; }
        }
        resolve({ status: res.statusCode, body: parsed });
      });
      res.on("error", reject);
    });
    req.on("timeout", () => {
      req.destroy(new Error("request timed out after " + REQUEST_TIMEOUT_MS + "ms"));
    });
    req.on("error", reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

function createProfileClient({ log, relayUrl }) {
  const httpBase = deriveHttpBase(relayUrl);
  const token = ensureToken(log);

  // PIDs we've already successfully paired in this sidecar lifetime. Used
  // as a hint only — we still let the server be the source of truth via
  // the 401-then-pair flow. Cleared on successful re-pair.
  const pairedPids = new Set();

  // Single in-flight retry slot. Holds the most recent failed payload and
  // when it was queued; a fresh `profile_upsert` overwrites it.
  let pending = null; // { payload, queuedAt }
  let retryTimer = null;

  function setPending(payload) {
    pending = { payload, queuedAt: Date.now() };
    if (!retryTimer) {
      retryTimer = setInterval(() => { void tryFlushPending(); }, RETRY_INTERVAL_MS);
      retryTimer.unref();
    }
  }

  function clearPending() {
    pending = null;
    if (retryTimer) {
      clearInterval(retryTimer);
      retryTimer = null;
    }
  }

  async function tryFlushPending() {
    if (!pending) return;
    if (Date.now() - pending.queuedAt > MAX_PENDING_AGE_MS) {
      log(`[PROFILE] Dropping pending upsert (age > ${MAX_PENDING_AGE_MS / 60000}min)`);
      clearPending();
      return;
    }
    log(`[PROFILE] Retrying pending upsert for ${pending.payload.prometheusId}`);
    await sendUpsert(pending.payload, { fromRetry: true });
  }

  async function pair(prometheusId) {
    log(`[PROFILE] POST /api/auth/pair for ${prometheusId}`);
    return jsonRequest({
      baseUrl: httpBase,
      method: "POST",
      pathName: "/api/auth/pair",
      body: { prometheusId, token },
      log,
    });
  }

  async function putProfile(payload) {
    return jsonRequest({
      baseUrl: httpBase,
      method: "PUT",
      pathName: "/api/profiles/" + payload.prometheusId,
      headers: { Authorization: "Bearer " + token },
      body: payload,
      log,
    });
  }

  // Returns { ok, status, terminal } — `terminal: true` means do not retry.
  async function sendUpsert(payload, opts = {}) {
    const { fromRetry = false } = opts;
    const pid = payload.prometheusId;

    let putRes;
    try { putRes = await putProfile(payload); }
    catch (err) {
      log(`[PROFILE] PUT transport error: ${err.message}; queueing for retry`);
      if (!fromRetry) setPending(payload);
      return { ok: false, status: 0, terminal: false };
    }

    if (putRes.status === 200) {
      pairedPids.add(pid);
      log(`[PROFILE] PUT /api/profiles/${pid} -> 200 (displayName=${payload.displayName})`);
      if (fromRetry) clearPending();
      return { ok: true, status: 200, terminal: true };
    }

    if (putRes.status === 401) {
      // Either we've never paired (cold start) OR the auth_tokens row was
      // deleted server-side (maintainer recovery). Try to pair and retry
      // PUT once.
      pairedPids.delete(pid);
      let pairRes;
      try { pairRes = await pair(pid); }
      catch (err) {
        log(`[PROFILE] PAIR transport error: ${err.message}; queueing for retry`);
        if (!fromRetry) setPending(payload);
        return { ok: false, status: 0, terminal: false };
      }

      if (pairRes.status === 201) {
        pairedPids.add(pid);
        log(`[PROFILE] paired ${pid}, retrying PUT`);
        let retryRes;
        try { retryRes = await putProfile(payload); }
        catch (err) {
          log(`[PROFILE] PUT-after-pair transport error: ${err.message}; queueing for retry`);
          if (!fromRetry) setPending(payload);
          return { ok: false, status: 0, terminal: false };
        }
        if (retryRes.status === 200) {
          log(`[PROFILE] PUT-after-pair -> 200 for ${pid}`);
          if (fromRetry) clearPending();
          return { ok: true, status: 200, terminal: true };
        }
        log(`[PROFILE] [ERR] PUT-after-pair -> ${retryRes.status}: ${JSON.stringify(retryRes.body)}; not retrying`);
        if (fromRetry) clearPending();
        return { ok: false, status: retryRes.status, terminal: true };
      }

      if (pairRes.status === 409) {
        // The relay has a different token bound to this Prometheus ID. The
        // sidecar can't break out of this without maintainer help (see the
        // 409 hint shape in server/api/profile/index.js). Surface a clear
        // log line and stop retrying — silent retry would just spin scrypt
        // on the relay forever.
        log(`[PROFILE] [ERR] PAIR -> 409: prometheusId already paired with a different token. Maintainer recovery required: ${JSON.stringify(pairRes.body)}`);
        if (fromRetry) clearPending();
        return { ok: false, status: 409, terminal: true };
      }

      log(`[PROFILE] [ERR] PAIR -> ${pairRes.status}: ${JSON.stringify(pairRes.body)}; queueing for retry`);
      if (!fromRetry) setPending(payload);
      return { ok: false, status: pairRes.status, terminal: false };
    }

    if (putRes.status === 403) {
      // Cross-PID — we presented a token bound to a different Prometheus
      // ID. The token file on disk is "wrong" for this game session. Two
      // possible causes: (a) the user logged in with a different Odyssey
      // account than the one this token paired against, (b) the token
      // file got copied across machines/accounts somehow. Either way the
      // sidecar can't fix this — stop retrying so we don't burn scrypt
      // calls on a hopeless request.
      log(`[PROFILE] [ERR] PUT -> 403: token belongs to a different Prometheus ID than ${pid}. Token-file mismatch — delete %LOCALAPPDATA%\\OSPlus\\token and relaunch to re-pair.`);
      if (fromRetry) clearPending();
      return { ok: false, status: 403, terminal: true };
    }

    if (putRes.status >= 500 || putRes.status === 0) {
      log(`[PROFILE] [ERR] PUT -> ${putRes.status}: ${JSON.stringify(putRes.body)}; queueing for retry`);
      if (!fromRetry) setPending(payload);
      return { ok: false, status: putRes.status, terminal: false };
    }

    // 4xx other than 401/403 (most commonly 400 from a malformed payload)
    // is a code bug, not a transient failure — log and stop.
    log(`[PROFILE] [ERR] PUT -> ${putRes.status}: ${JSON.stringify(putRes.body)}; not retrying (treat as code bug)`);
    if (fromRetry) clearPending();
    return { ok: false, status: putRes.status, terminal: true };
  }

  // Wire-boundary entry point. Validates the IPC payload, then fires the
  // upsert flow. Per node-conventions: log and drop on bad input; never
  // throw out into the IPC dispatcher.
  async function handleProfileUpsert(rawMsg) {
    if (!rawMsg || typeof rawMsg !== "object") {
      log(`[PROFILE] [!] profile_upsert dropped: not an object`);
      return;
    }
    const pid = typeof rawMsg.prometheusId === "string" ? rawMsg.prometheusId.trim() : "";
    if (!PID_RE.test(pid)) {
      log(`[PROFILE] [!] profile_upsert dropped: invalid prometheusId shape (${pid.length} chars)`);
      return;
    }
    const displayName = typeof rawMsg.displayName === "string" ? rawMsg.displayName.trim() : "";
    if (!displayName) {
      log(`[PROFILE] [!] profile_upsert dropped: missing displayName`);
      return;
    }

    // Build the canonical payload — drop the IPC envelope fields (`type`,
    // `ts`) and pass through only what the REST API expects.
    const payload = {
      prometheusId:    pid,
      steamId:         optStr(rawMsg.steamId),
      displayName,
      currentPlatform: optStr(rawMsg.currentPlatform),
      logoId:          optStr(rawMsg.logoId),
      nameplateId:     optStr(rawMsg.nameplateId),
      emoticonId:      optStr(rawMsg.emoticonId),
      titleId:         optStr(rawMsg.titleId),
      masteryLevel:    optInt(rawMsg.masteryLevel),
    };

    await sendUpsert(payload);
  }

  function shutdown() {
    if (retryTimer) {
      clearInterval(retryTimer);
      retryTimer = null;
    }
  }

  log(`[PROFILE] HTTP base: ${httpBase} (derived from ${relayUrl})`);
  return { handleProfileUpsert, shutdown, _httpBase: httpBase, _token: token };
}

function optStr(v) {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t === "" || t === "None" ? null : t;
}

function optInt(v) {
  if (v === null || v === undefined) return null;
  const n = typeof v === "number" ? v : parseInt(String(v), 10);
  return Number.isFinite(n) && Number.isInteger(n) ? n : null;
}

module.exports = { createProfileClient, deriveHttpBase, TOKEN_FILE };
