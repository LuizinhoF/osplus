# OSPlus — Vision (v1) — SUPERSEDED

> **This document is archived.** It has been superseded by [`docs/product.md`](../../product.md) (product definition) and [`docs/decisions/`](../) (ADR-based architectural deliberation).
>
> **Why archived (2026-04-23).** This document locked four architectural commitments without deliberation — written directly into a doc titled "v1 — locked" with no record of alternatives considered. That made premature choices rigid, which made feature work fight the rules instead of learning from them.
>
> The meta-problem the archive solves: the decisions below were reasonable for a solo/friend-group project and are not all appropriate for the now-stated public-OS-community ambition. Rather than silently mutate them, the whole document is retired and the decisions that still matter are being re-examined as ADRs where options actually get compared honestly.
>
> **Do not treat the "locks" below as current architectural commitments.** Three of them (identity, profile storage, ephemeral state) are flagged in [`docs/product.md`](../../product.md) as first-priority ADR work and will be re-decided there. The fourth (schema grows on demand) has been preserved as a policy, not an architectural lock.
>
> **Why preserved rather than deleted.** A future agent proposing one of these same "locks" should be able to find this doc and see that it was tried — with this rationale — and retired for a specific reason. The archive is a hedge against re-making the same decisions with the same blind spots.
>
> **Original content follows unmodified below this line.**

---

# OSPlus — Vision (v1)

This document locks the **architectural commitments** that future features build on. It is intentionally narrow: only the decisions that, if changed later, would force a rewrite of multiple unrelated subsystems.

Everything not locked here is a downstream feature decision and belongs to the agent shipping the feature, guided by the `feature-design` skill.

If a future change invalidates a lock, it gets a real conversation with the user and a `docs/learnings/` entry. Don't quietly drift.

## Status

**v1 — locked 2026-04-04.** Drives the upcoming `feat/chat-presence-and-colors` work and the standing-up of `server/profile/`.

---

## Lock 1 — Identity model

The stable per-player identifier is **claimed SteamID** (`steamid64` as string). Display name is **game-derived** (read from the running client; refreshed on connect).

| Aspect | v1 commitment |
|---|---|
| Stable ID | `steamId` (string, 17-digit `steamid64`) |
| Source | Claimed by the sidecar at handshake. No verification. |
| Display name | Read from the game per-session, sent alongside `steamId`, can change between sessions |
| Trust model | **Trust-on-claim.** A determined attacker can spoof another player's `steamId`. v1 accepts this. |

**Why claimed SteamID over alternatives:**
- It already exists, is stable across reinstalls, and matches a public identity the player already understands.
- It avoids inventing an OSPlus-specific account system before there's a reason to.
- It does not preclude future verification (Steam Web API ticket exchange, Odyssey OAuth, etc.) — those layer on top by *upgrading* a `steamId` from "claimed" to "verified" without changing the schema.

**What this rules out for v1:**
- Anti-impersonation guarantees. Don't build features whose security model depends on `steamId` being authentic (e.g., currency, trading, moderation actions).
- Cross-account features (one player → multiple Steam accounts).

## Lock 2 — Profile module exists, REST API, in-process

A profile module ships now. It is a **REST API** (not WebSocket-coupled), backed by **SQLite** on the relay VM, and lives in `server/profile/` as a module of the existing relay process.

| Aspect | v1 commitment |
|---|---|
| API surface | HTTP REST, mounted on the relay's existing HTTP server |
| Storage | SQLite, single file on the relay VM (path TBD by the implementing agent) |
| Process model | **In-process with the relay** for v1. Same Node.js runtime, same deploy unit. |
| Future move | Designed to extract into its own service later without changing callers. Module boundary inside the codebase enforces this. |

**Why REST and not WebSocket-coupled:**
- Profile reads/writes are request/response, not streaming. WebSocket framing is overhead.
- A REST profile API is reachable from a future web client (account portal, etc.) without going through the game.
- Decouples profile lifecycle from chat-room lifecycle. A player can have a profile without being in a room.

**Why in-process for v1:**
- One deploy unit, one set of logs, one TLS certificate, one set of credentials. Cheaper to operate.
- The migration cost from "module in the relay process" to "separate service" is small if the module boundary is clean. The migration cost from "tangled into relay handlers" to "separate service" is large. The lock is the **boundary**, not the **process**.

**What this rules out for v1:**
- Putting profile fields directly into the relay's in-memory room state. Profile data goes through the module's API, not through ad-hoc shared structs.
- WebSocket messages that *carry* profile data inline. WebSocket messages may carry a `steamId`; the receiver looks the profile up via REST (or via an in-process call that uses the same module API).

## Lock 3 — Profile schema starts identity-only and grows on demand

The v1 profile schema is identity-only:

```
profile {
  steamId:     string  PK  -- 17-digit steamid64
  displayName: string      -- last seen game display name
  createdAt:   timestamp
  updatedAt:   timestamp
}
```

**Fields are added when a feature actually needs them, not before.** No speculative columns. No "we'll probably want X" pre-additions.

**Why this is a lock and not just an "initial state":**
- It commits to the *policy* of demand-driven schema growth. The policy is what prevents the schema from accreting half-designed fields based on Slack-tier conversations.
- The policy means every new column comes with the feature that uses it, in the same branch, with the same scrutiny.

**Process for adding a field:**
1. The feature requiring the field opens a branch.
2. The agent shipping the feature uses the `feature-design` skill (Phase 4) to surface the design axes for the field — allocation, scope, default, mutability, validation, presentation.
3. The vision doc gets a one-line note in the "Schema growth log" section below.
4. A migration is added (mechanism TBD — see open questions).

### Schema growth log

(empty — additions get a row here with date, field, motivating feature, learning slug if any)

## Lock 4 — Ephemeral state lives on the relay

Anything that is *current-session-only* (room membership, presence, in-flight messages, transient flags) is owned by the relay process. Not the client. Not a separate ephemeral-state service.

| Aspect | v1 commitment |
|---|---|
| Owner | Relay (in-memory) |
| Persistence | None — restart loses ephemeral state by design |
| Recovery | Clients re-handshake on reconnect; presence rebuilds from re-joins |
| Snapshotting | Per-feature; default is "no snapshot, restart is a clean slate" |

**Why the relay and not the client:**
- Late joiners need to see who is already present. Client-only state cannot serve a late joiner.
- A single source of truth eliminates "client A and client B disagree about who's in the room" failure modes.

**Why not a separate ephemeral-state service (e.g., Redis):**
- Premature for v1's load (a few dozen concurrent connections).
- Adds another moving part to operate, monitor, and authenticate.
- The migration cost is low *if* the relay code keeps ephemeral state behind a small interface (get/set/list-by-room). That hygiene is the lock; the storage choice is not.

**What this rules out for v1:**
- Persisting ephemeral state to SQLite "just in case." Persistence is a deliberate per-feature decision, not a default.
- Treating client-side state as authoritative for shared facts. Client state is a *cache*, not a source.

---

## Open questions (`[TBD]`)

These are intentionally unanswered in v1 because no current feature forces an answer. The first feature that requires one of these answers it, in its own branch, with a design pass.

- `[TBD]` **SteamID verification path.** When does "claimed" become "verified," and what does verified unlock? (Forced by: anything trust-sensitive — currency, moderation, trading.)
- `[TBD]` **Currency model.** One currency or two? Caps? Earn rates? (Forced by: any feature that grants or spends currency.)
- `[TBD]` **Social primitives.** Friends list source of truth — ours, Steam's, or the game's? DMs in scope? (Forced by: friends/DMs/party features.)
- `[TBD]` **Analytics scope.** What gets logged for product decisions vs invasive? (Forced by: first analytics use, or first privacy concern raised.)
- `[TBD]` **Account portal.** Web UI for profile management — needed, or in-game only? (Forced by: any setting that's awkward to expose in-game.)
- `[TBD]` **Schema migration mechanism.** How a new field actually rolls out (manual SQL, migration tool, drift-tolerant reads). (Forced by: the *second* schema-growing feature; the first can do whatever and document.)
- `[TBD]` **Versioning / compatibility policy.** Mod can be older than server; server can be older than mod. What's the contract? (Forced by: first breaking protocol change.)
- `[TBD]` **Premium / monetization.** Whether OSPlus ever takes money, and how. (Forced by: a real reason to charge — none today.)

---

## What is *not* in scope of this document

- **Specific feature designs** (chat presence protocol, color allocation, channel switching, etc.). These belong in feature branches and use the `feature-design` skill.
- **Implementation details** (which SQLite library, which HTTP framework, file paths). These belong to the implementing agent.
- **Operational policy** (backup cadence, monitoring, rotation). These live in `docs/ops/`.
- **Engine / RE knowledge.** That's `KNOWLEDGEBASE.md` and `docs/learnings/`.

If you're an agent reading this and your feature work seems to require *changing* a lock above, stop and surface the conflict. Locks change with conversation, not by drift.
