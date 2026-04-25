/**
 * Profile + auth schema for `osplus.sqlite3`.
 * --------------------------------------------
 * Per ADR 0002 (M-i: drop and recreate). At N=1 schema we don't ship a
 * migration framework — `applySchema()` runs `CREATE TABLE IF NOT EXISTS`
 * idempotently on every relay start. When the schema next changes, the
 * recovery procedure is a manual one-liner (`DROP TABLE` + restart) until
 * the second schema-changing feature lands and earns the framework.
 *
 * Column nullability rationale:
 *   - `prometheus_id`: PK; identity is meaningless without it.
 *   - `display_name`: NOT NULL because the sidecar gates emission on a
 *     friendly name being resolved (see profile.lua's `tryEmit`); a NULL
 *     here would mean we let the synthetic `Player-XXXX` fallback through.
 *     Schema-level enforcement keeps that invariant honest.
 *   - All other cosmetic columns are nullable (per ADR 0002 Notes — future
 *     non-Steam platforms may not surface every field).
 *   - `created_at` / `updated_at` are mod-side ISO-8601 strings stamped by
 *     the relay; readable in the DB without epoch arithmetic.
 *
 * Auth columns (`auth_tokens`):
 *   - `token_hash` BLOB: scrypt-derived 64-byte key (Node `crypto.scrypt`
 *     defaults: N=2^14, r=8, p=1, keylen=64).
 *   - `scrypt_salt` BLOB: 16-byte random salt, generated at pair time.
 *   - `last_seen_at` advances on every successful authenticated request —
 *     the maintainer-recovery runbook reads it to confirm whether a paired
 *     install is still active before deleting the row.
 */

const SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS profiles (
  prometheus_id     TEXT    PRIMARY KEY,
  steam_id          TEXT,
  display_name      TEXT    NOT NULL,
  current_platform  TEXT,
  logo_id           TEXT,
  nameplate_id      TEXT,
  emoticon_id       TEXT,
  title_id          TEXT,
  mastery_level     INTEGER,
  created_at        TEXT    NOT NULL,
  updated_at        TEXT    NOT NULL
);

CREATE TABLE IF NOT EXISTS auth_tokens (
  prometheus_id  TEXT    PRIMARY KEY,
  token_hash     BLOB    NOT NULL,
  scrypt_salt    BLOB    NOT NULL,
  created_at     TEXT    NOT NULL,
  last_seen_at   TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_profiles_updated_at ON profiles(updated_at);
`;

function applySchema(db) {
  db.exec(SCHEMA_SQL);
}

module.exports = { applySchema, SCHEMA_SQL };
