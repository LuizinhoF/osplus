/**
 * Profile + auth route handlers (per ADR 0002).
 * ---------------------------------------------
 * Three routes:
 *   POST /api/auth/pair           — TOFU bind a token to a Prometheus ID. No
 *                                   auth (the request *is* the pairing).
 *                                   `409` if the PID is already paired.
 *   PUT  /api/profiles/{pid}      — Upsert profile row. Auth required;
 *                                   cross-PID = `403`.
 *   GET  /api/profiles/{pid}      — Read profile row. Auth required;
 *                                   cross-PID = `403`. `404` if absent.
 *
 * Wire boundary policy (per node-conventions.mdc):
 *   - Per-field validation at the boundary; reject with `400` + JSON body.
 *   - Errors logged + JSON-replied; never throw out of a handler.
 *   - Body cap is enforced upstream by the API dispatcher (see `api/index.js`).
 *
 * Maintainer-recovery procedure (token-loss recovery, ADR 0002):
 *   `sqlite3 osplus.sqlite3 "DELETE FROM auth_tokens WHERE prometheus_id='<pid>'"`
 *   then the next pair from a fresh client succeeds. The 409 hint below
 *   surfaces this path to the human running the curl when they hit it.
 */

const crypto = require("crypto");
const { scryptHash, SCRYPT_KEYLEN } = require("../middleware/auth");

// 24-char lowercase hex (MongoDB ObjectID shape, per Clarion v2 docs).
const PID_RE = /^[0-9a-f]{24}$/;

// 16 bytes random base64url-no-pad ≈ 22 chars; 32 bytes ≈ 43 chars. Cap at
// 256 to bound an attacker's scrypt-cost amplification (each /pair attempt
// triggers one scrypt hash).
const TOKEN_RE = /^[A-Za-z0-9_\-]{16,256}$/;

function nowIso() {
  return new Date().toISOString();
}

function writeJson(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(payload),
  });
  res.end(payload);
}

function badRequest(res, msg) {
  writeJson(res, 400, { error: msg });
}

// Coerce optional string field to a trimmed non-empty string or null. Caps
// length so a malicious client can't push 10 MB into a TEXT column.
function optStr(v, maxLen = 128) {
  if (v === null || v === undefined) return null;
  if (typeof v !== "string") return null;
  const t = v.trim();
  if (t === "" || t === "None") return null;
  if (t.length > maxLen) return t.slice(0, maxLen);
  return t;
}

function optInt(v) {
  if (v === null || v === undefined) return null;
  const n = typeof v === "number" ? v : parseInt(String(v), 10);
  if (!Number.isFinite(n) || !Number.isInteger(n)) return null;
  return n;
}

function reqStr(v, maxLen = 128) {
  const s = optStr(v, maxLen);
  return s === null ? null : s;
}

function createProfileRoutes({ db, log, auth }) {
  // Prepared statements (process-lifetime caches).
  const insertToken = db.prepare(`
    INSERT INTO auth_tokens (prometheus_id, token_hash, scrypt_salt, created_at, last_seen_at)
    VALUES (?, ?, ?, ?, ?)
  `);
  const selectToken = db.prepare(
    "SELECT prometheus_id FROM auth_tokens WHERE prometheus_id = ?"
  );
  const upsertProfile = db.prepare(`
    INSERT INTO profiles (
      prometheus_id, steam_id, display_name, current_platform,
      logo_id, nameplate_id, emoticon_id, title_id, mastery_level,
      created_at, updated_at
    ) VALUES (
      @prometheusId, @steamId, @displayName, @currentPlatform,
      @logoId, @nameplateId, @emoticonId, @titleId, @masteryLevel,
      @createdAt, @updatedAt
    )
    ON CONFLICT(prometheus_id) DO UPDATE SET
      steam_id         = excluded.steam_id,
      display_name     = excluded.display_name,
      current_platform = excluded.current_platform,
      logo_id          = excluded.logo_id,
      nameplate_id     = excluded.nameplate_id,
      emoticon_id      = excluded.emoticon_id,
      title_id         = excluded.title_id,
      mastery_level    = excluded.mastery_level,
      updated_at       = excluded.updated_at
  `);
  const selectProfile = db.prepare(`
    SELECT prometheus_id, steam_id, display_name, current_platform,
           logo_id, nameplate_id, emoticon_id, title_id, mastery_level,
           created_at, updated_at
    FROM profiles WHERE prometheus_id = ?
  `);

  // POST /api/auth/pair — TOFU bind. Body: {prometheusId, token}.
  async function handlePair(req, res, body) {
    let parsed;
    try { parsed = JSON.parse(body); }
    catch { return badRequest(res, "invalid JSON"); }

    if (!parsed || typeof parsed !== "object") return badRequest(res, "expected object body");
    const prometheusId = optStr(parsed.prometheusId, 24);
    const token = optStr(parsed.token, 256);
    if (!prometheusId || !PID_RE.test(prometheusId)) {
      return badRequest(res, "prometheusId must be 24-char lowercase hex");
    }
    if (!token || !TOKEN_RE.test(token)) {
      return badRequest(res, "token must match [A-Za-z0-9_-]{16,256}");
    }

    // Conflict check before doing any scrypt work — cheap row lookup
    // short-circuits the expensive hash on a known-bad request.
    let existing;
    try { existing = selectToken.get(prometheusId); }
    catch (err) {
      log(`[AUTH] pair lookup failed: ${err.message}`);
      return writeJson(res, 500, { error: "internal error" });
    }
    if (existing) {
      // Maintainer-recovery hint surfaced to whoever's looking at the
      // response (almost always the person running curl during a recovery).
      // The sidecar treats 409 as terminal for this session.
      return writeJson(res, 409, {
        error: "prometheusId already paired",
        hint: "maintainer must DELETE FROM auth_tokens WHERE prometheus_id='" + prometheusId + "' to allow re-pair",
      });
    }

    let salt, tokenHash;
    try {
      salt = crypto.randomBytes(16);
      tokenHash = await scryptHash(token, salt);
    } catch (err) {
      log(`[AUTH] scrypt failed during pair: ${err.message}`);
      return writeJson(res, 500, { error: "internal error" });
    }

    const ts = nowIso();
    try {
      insertToken.run(prometheusId, tokenHash, salt, ts, ts);
    } catch (err) {
      // Race: another concurrent pair won between our SELECT and INSERT.
      // SQLite UNIQUE-constraint violation surfaces as a SqliteError; map
      // to the same 409 the cooperative path uses so clients see one shape.
      if (err && /UNIQUE|constraint/i.test(err.message)) {
        return writeJson(res, 409, {
          error: "prometheusId already paired",
          hint: "maintainer must DELETE FROM auth_tokens WHERE prometheus_id='" + prometheusId + "' to allow re-pair",
        });
      }
      log(`[AUTH] pair insert failed: ${err.message}`);
      return writeJson(res, 500, { error: "internal error" });
    }

    log(`[AUTH] paired prometheusId=${prometheusId}`);
    return writeJson(res, 201, { prometheusId, pairedAt: ts });
  }

  // PUT /api/profiles/{pid} — upsert profile row. Auth required.
  async function handlePut(req, res, body, urlPid) {
    const authResult = await auth.authenticate(req);
    if (!authResult.ok) return writeJson(res, authResult.status, { error: authResult.error });
    if (authResult.prometheusId !== urlPid) {
      return writeJson(res, 403, { error: "token does not match url prometheusId" });
    }

    let parsed;
    try { parsed = JSON.parse(body); }
    catch { return badRequest(res, "invalid JSON"); }
    if (!parsed || typeof parsed !== "object") return badRequest(res, "expected object body");

    const bodyPid = optStr(parsed.prometheusId, 24);
    if (bodyPid && bodyPid !== urlPid) {
      return badRequest(res, "body prometheusId must match url prometheusId");
    }

    const displayName = reqStr(parsed.displayName, 64);
    if (!displayName) return badRequest(res, "displayName is required");

    const row = {
      prometheusId:    urlPid,
      steamId:         optStr(parsed.steamId, 32),
      displayName,
      currentPlatform: optStr(parsed.currentPlatform, 32),
      logoId:          optStr(parsed.logoId, 64),
      nameplateId:     optStr(parsed.nameplateId, 64),
      emoticonId:      optStr(parsed.emoticonId, 64),
      titleId:         optStr(parsed.titleId, 64),
      masteryLevel:    optInt(parsed.masteryLevel),
      // Upsert: createdAt is only consulted on first insert; the ON CONFLICT
      // clause leaves the existing created_at untouched.
      createdAt:       nowIso(),
      updatedAt:       nowIso(),
    };

    try {
      upsertProfile.run(row);
    } catch (err) {
      log(`[PROFILE] upsert failed for ${urlPid}: ${err.message}`);
      return writeJson(res, 500, { error: "internal error" });
    }

    let stored;
    try { stored = selectProfile.get(urlPid); }
    catch (err) {
      log(`[PROFILE] post-upsert read failed for ${urlPid}: ${err.message}`);
      return writeJson(res, 500, { error: "internal error" });
    }

    log(`[PROFILE] upsert prometheusId=${urlPid} displayName=${displayName}`);
    return writeJson(res, 200, rowToWire(stored));
  }

  // GET /api/profiles/{pid} — read profile row. Auth required.
  async function handleGet(req, res, urlPid) {
    const authResult = await auth.authenticate(req);
    if (!authResult.ok) return writeJson(res, authResult.status, { error: authResult.error });
    if (authResult.prometheusId !== urlPid) {
      return writeJson(res, 403, { error: "token does not match url prometheusId" });
    }

    let row;
    try { row = selectProfile.get(urlPid); }
    catch (err) {
      log(`[PROFILE] read failed for ${urlPid}: ${err.message}`);
      return writeJson(res, 500, { error: "internal error" });
    }
    if (!row) return writeJson(res, 404, { error: "no profile for prometheusId" });
    return writeJson(res, 200, rowToWire(row));
  }

  return { handlePair, handlePut, handleGet, PID_RE };
}

// SQLite snake_case → wire camelCase. Keeping this at the wire boundary
// means the storage layer can stay snake-case-pure (idiomatic SQL) while
// the JSON API stays camelCase (idiomatic JS, matches the IPC shape).
function rowToWire(row) {
  return {
    prometheusId:    row.prometheus_id,
    steamId:         row.steam_id,
    displayName:     row.display_name,
    currentPlatform: row.current_platform,
    logoId:          row.logo_id,
    nameplateId:     row.nameplate_id,
    emoticonId:      row.emoticon_id,
    titleId:         row.title_id,
    masteryLevel:    row.mastery_level,
    createdAt:       row.created_at,
    updatedAt:       row.updated_at,
  };
}

module.exports = { createProfileRoutes, PID_RE };
