# ADR 0002 — Profile + capture storage and per-request auth

| Field | Value |
|---|---|
| Status | `accepted` |
| Date | 2026-04-25 |
| Forcing feature | `feat/in-game-profile-mvp` (Stage 5 — substrate identity resolved per ADR 0001 v36; next concrete step is "create our user in the mod server") |
| Supersedes | `docs/decisions/_archive/vision-v1-superseded.md` → Lock 2 (in-process SQLite REST module on the relay), partially. The transport shape is re-affirmed; the schema is replaced (per ADR 0001's `prometheus_id` PK); per-request auth is added. |
| Superseded by | — |

## Decision

Profile rows and raw match captures both live **server-side on the OCI VM**, in **two SQLite files** owned by the **existing chat-relay process**, served over **HTTP REST**, gated by **per-install bearer tokens** that bind to a Prometheus ID on first contact.

Concretely:

- **S-A** — Single Node process (the chat relay) owns persistence. Module boundary stays clean inside the code; physical extraction (S-B) becomes mechanical when scale forces it.
- **T-β** — HTTP REST routes on the relay's existing `http.Server`. No new ports, no new TLS termination — Caddy already covers `play-osplus.duckdns.org`.
- **R-Y** — Two SQLite files: `data/osplus.sqlite3` (profile + auth) and `data/osplus_captures.sqlite3` (captures). Independent write locks, independent backup cadence.
- **M-i** — Drop and recreate. No production data exists; a migration framework at N=1 schema is theatre.
- **A-2** — Sidecar generates a random token on first run, stores it in `%LOCALAPPDATA%\OSPlus\token` with restrictive ACLs. First call to `POST /auth/pair` TOFU-binds the token to the player's Prometheus ID. Subsequent requests carry the token; mismatch = `401`. Cross-PID access = `403`.

A-2 is consistent with ADR 0001's T-α (trust-on-claim identity) — it verifies the *request* came from the player who first claimed the PID, not the *identity claim* itself. A-3 (Steam ticket validation) would amend ADR 0001 and is named only as a Revisit trigger.

## Why these picks (one paragraph each)

- **S-A over S-B.** At ~25 users, a second systemd unit is real ongoing operational cost for hypothetical failure-isolation benefit. Keep the boundary clean inside the code so extraction is mechanical when load forces it; don't pre-pay the cost on speculation.
- **T-β over T-α / T-γ.** HTTP gives request/response shape for free; multiplexing it on top of the chat WebSocket pays a correlation-ID-convention tax for nothing and couples profile lifecycle to chat-room lifecycle. A separate WS server is operational cost without a benefit T-β doesn't already give.
- **R-Y over R-X.** Splitting captures into a separate file costs ~10 lines and buys: capture-burst writes don't share a write lock with profile reads, captures get their own backup/retention cadence, and a bug in capture code can't corrupt profile data.
- **M-i over M-iii.** Zero production data; a migration framework at N=1 schema is overhead. Revisit when the second schema-changing feature lands.
- **A-2 over A-1, A-3, A-4.** A-1 (shared service token) fails catastrophically if the secret leaks (and a secret distributed to N client installs eventually does). A-3 (Steam ticket validation) is cryptographically stronger but requires Steam publisher registration and Steam-couples the auth path. A-4 (Discord OAuth) forces a web portal at MVP. A-2 satisfies "not easily exploited" against the realistic threat (random-internet abuse) without external dependencies.

## What this commits us to

- **Persistence module** under `server/` (new), owning two `Database()` instances. Mounted on the relay's existing `http.Server`. Module boundary enforced by code-comment guarantee at the call site in `server/index.js` ("only call the module's exported functions; never touch `db` directly").
- **Schema:**
  - `profiles(prometheus_id PK, steam_id, display_name, current_platform, logo_id, nameplate_id, emoticon_id, title_id, mastery_level, created_at, updated_at)`
  - `auth_tokens(prometheus_id PK, token_hash, created_at, last_seen_at)` — bcrypt or argon2 hashed
  - `match_captures` + `redirect_events` in `osplus_captures.sqlite3` — exact columns are the capture-feature implementation's call (this ADR decides *where*, not *what's in it*)
- **HTTP routes:**
  - `POST /auth/pair` — first-time TOFU bind. No auth (the request *is* the pairing). Rate-limited per IP.
  - `PUT/GET /profiles/{prometheusId}` — auth-required. Cross-PID = `403`.
  - `POST /captures` — submit a match batch. Auth-required.
  - `GET /captures?since=<iso8601>` — read own captures (paged). Auth-required.
  - All versionless for MVP (no `/v1/` prefix); add it the day a breaking change lands.
- **Sidecar gains:**
  - Token storage at `%LOCALAPPDATA%\OSPlus\token` (mode `0600` POSIX / restrictive ACL Windows)
  - HTTP client for `/auth/pair`, `/profiles`, `/captures`
  - Pending-captures retry buffer at `%LOCALAPPDATA%\OSPlus\pending_captures.jsonl` for transient HTTP failures
- **Mod `profile.lua`:** subscribe via `identity.onPrometheusIdResolved(cb)`; emit one `profile:upsert` IPC message per session containing the canonical loadout fields.
- **Token-loss recovery at MVP scale:** maintainer manually deletes the `auth_tokens` row for that PID, allowing re-pair. Self-serve recovery is a future ADR.
- **`server/index.js` header update:** drop the "no persistence by design" claim.

## What this rules out (until superseded)

- Anonymous reads, cross-user reads, cross-account capture visibility.
- Independent redeploy of profile/captures vs chat (single process).
- Schema migrations (drop-and-recreate only).
- Versioned wire format (no `/v1/` prefix yet).
- Cryptographic identity verification (A-2 is TOFU; ADR 0001's T-α is trust-on-claim).
- Self-serve token recovery.

## Revisit when

- Second schema-changing feature lands → adopt M-iii (versioned migrations) before merging.
- Active concurrent users sustainedly above ~150 → reopen S (worker thread, S-B, or a different storage engine).
- TOFU squatting incident in the wild → reopen A; A-3 (Steam ticket) likely promoted.
- Account-portal-style web client built → browser-shaped auth ADR (A-2's `%LOCALAPPDATA%\token` doesn't apply).
- `better-sqlite3` build breaks on the OCI VM → reconsider storage engine.
- Token-loss support load on the maintainer becomes recurring → self-serve recovery ADR.
- Future feature requires identity-claim verification beyond TOFU → reopen A; would amend ADR 0001's T-α.

## Considered and rejected

- **S-B** — Separate `osplus-profile.service` process. Premature operational cost at MVP scale; folded into the *Revisit when* triggers.
- **S-C, S-D** — Sidecar-local source-of-truth (with or without a server cache). Maintainer instruction: server-side only.
- **T-α** — Multiplex profile messages over the chat WebSocket. Re-implements HTTP poorly; couples profile lifecycle to chat-room lifecycle.
- **T-γ** — Separate WS server for profile. Operational cost without benefit.
- **M-ii** — One-time in-place SQL migration. Same end state as M-i with extra complexity (and partial-by-design — needs a player live in-game).
- **M-iii** — Versioned migrations from day 1. Premature at N=1 schema; trigger named.
- **R-W** — Sidecar-local raw captures. Maintainer-rejected (server-side mandatory).
- **R-X** — Profile + captures in one DB file. Lock contention + blast-radius for cheap separation.
- **R-Z** — Defer raw capture to a follow-up ADR. Forcing feature can't wait.
- **A-1** — Shared `RELAY_TOKEN`-style service token. Catastrophic failure when the secret leaks.
- **A-3** — Steam Web API ticket validation. Steam publisher registration + Steam-coupling cost; would amend ADR 0001. Promoted-to-trigger if A-2 fails.
- **A-4** — Discord (or other third-party) OAuth. Forces a web portal at MVP.

## Related

- **Forced by:** [`docs/features/in-game-profile-mvp.md`](../features/in-game-profile-mvp.md)
- **Relies on:** [`0001-identity-model.md`](./0001-identity-model.md) (accepted) — `prometheus_id` PK, T-α trust-on-claim
- **Supersedes:** [`_archive/vision-v1-superseded.md`](./_archive/vision-v1-superseded.md) → Lock 2 (partial — see header)
- **Code locations** (post-acceptance, to be implemented):
  - `server/persistence/` (new module — two DBs, auth middleware, HTTP handler)
  - `server/index.js` (mount, module-boundary code-comment, header update)
  - `server/deploy/install-relay.sh` (verify `npm install` builds `better-sqlite3`)
  - `sidecar/profile.js` + `sidecar/captures.js` (new)
  - `mod/OSPlus/scripts/profile.lua` (Prometheus-ID subscription, drop SteamID polling)

## Notes

- v1 of this ADR proposed R-W (sidecar-local captures) and "reuse `RELAY_TOKEN`" auth. v2 corrected after maintainer pushback: server-side everything, real auth, prototype is not load-bearing. Lesson kept for future ADRs in this repo: when product framing emphasizes durability/security/correlation, down-weight "cost-to-build" and "reuse-the-prototype" arguments.
- The cosmetic-loadout columns (`logo_id`, `nameplate_id`, `emoticon_id`, `title_id`, `mastery_level`) are a free option from ADR 0001's substrate work — `identity.lua`'s walk through `PMPlayerPublicProfile` already sees them. Surfacing them now costs one wider INSERT and saves the eventual unlockable-feature an extra round-trip per resolution. All nullable (future non-Steam launches may not surface every field).
