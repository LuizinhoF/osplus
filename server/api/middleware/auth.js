/**
 * Bearer-token auth middleware for the persistence module.
 * --------------------------------------------------------
 * Per ADR 0002 A-2 (per-install bearer + TOFU bind). Tokens are random
 * 32-byte values generated client-side at first run, scrypt-hashed at pair
 * time, and stored in `auth_tokens(prometheus_id PK, token_hash, scrypt_salt)`.
 *
 * Verify path on every authenticated request:
 *   1. Pull `Authorization: Bearer <token>` (case-insensitive scheme).
 *   2. Walk every row in `auth_tokens`, scrypt-hash the supplied token with
 *      that row's salt, and `timingSafeEqual` against the row's hash. The
 *      first match wins; the row's `prometheus_id` becomes `req.prometheusId`.
 *   3. Touch `last_seen_at` on the matched row.
 *
 * Why iterate every row instead of a token-keyed lookup:
 *   We don't store the plaintext token, so we can't index by it. Per-row
 *   scrypt is intentionally slow (~30-100ms each), so this is O(N * scryptCost)
 *   per request. At MVP scale (~25 users) that's ~1-3s worst case for an
 *   *invalid* token (must scan every row before failing). For the common
 *   case (valid token), early-exit on first match keeps it ~1 scrypt call.
 *
 * Scaling cliff (named so it isn't surprising later):
 *   At ~100 paired installs the worst-case invalid-token cost crosses ~10s.
 *   The fix is the standard "store HMAC(server_secret, token) as an indexed
 *   column for lookup, scrypt-verify only on the matched row" pattern. Not
 *   needed at MVP scale; revisit when N approaches the cliff.
 *
 * Cross-PID protection happens in the route handlers, not here — middleware
 * only proves "this request carries a known token." Routes that take a
 * `{prometheusId}` path parameter must verify it equals `req.prometheusId`
 * and respond `403` on mismatch.
 *
 * `pair` is the lone unauthenticated route — the request *is* the pairing.
 */

const crypto = require("crypto");

const SCRYPT_KEYLEN = 64;
const SCRYPT_OPTS = { N: 1 << 14, r: 8, p: 1, maxmem: 64 * 1024 * 1024 };

function scryptHash(token, salt) {
  return new Promise((resolve, reject) => {
    crypto.scrypt(token, salt, SCRYPT_KEYLEN, SCRYPT_OPTS, (err, key) => {
      if (err) return reject(err);
      resolve(key);
    });
  });
}

// Constant-time equality for two Buffers of equal length. timingSafeEqual
// throws on length mismatch — we pre-check to keep the call site simple.
function buffersEqual(a, b) {
  if (!Buffer.isBuffer(a) || !Buffer.isBuffer(b)) return false;
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

function extractBearer(req) {
  const h = req.headers["authorization"];
  if (typeof h !== "string") return null;
  const m = h.match(/^Bearer\s+([A-Za-z0-9_\-]+)$/i);
  return m ? m[1] : null;
}

function createAuthMiddleware({ db, log }) {
  // Prepared statements live for the process lifetime; safe to cache.
  const selectAllTokens = db.prepare(
    "SELECT prometheus_id, token_hash, scrypt_salt FROM auth_tokens"
  );
  const touchLastSeen = db.prepare(
    "UPDATE auth_tokens SET last_seen_at = ? WHERE prometheus_id = ?"
  );

  // Resolves to { ok, prometheusId, status, error }. Never throws on bad
  // input — wire boundary, log + drop per node-conventions.
  async function authenticate(req) {
    const token = extractBearer(req);
    if (!token) {
      return { ok: false, status: 401, error: "missing or malformed Authorization header" };
    }

    let rows;
    try {
      rows = selectAllTokens.all();
    } catch (err) {
      log(`[AUTH] DB read failed: ${err.message}`);
      return { ok: false, status: 500, error: "internal error" };
    }
    if (rows.length === 0) {
      return { ok: false, status: 401, error: "invalid token" };
    }

    for (const row of rows) {
      let candidate;
      try {
        candidate = await scryptHash(token, row.scrypt_salt);
      } catch (err) {
        log(`[AUTH] scrypt failed: ${err.message}`);
        continue;
      }
      if (buffersEqual(candidate, row.token_hash)) {
        try {
          touchLastSeen.run(new Date().toISOString(), row.prometheus_id);
        } catch (err) {
          log(`[AUTH] last_seen_at update failed: ${err.message}`);
        }
        return { ok: true, prometheusId: row.prometheus_id };
      }
    }

    return { ok: false, status: 401, error: "invalid token" };
  }

  return { authenticate };
}

module.exports = {
  createAuthMiddleware,
  scryptHash,
  buffersEqual,
  SCRYPT_KEYLEN,
  SCRYPT_OPTS,
};
