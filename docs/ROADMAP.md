# OSPlus — Roadmap

Forward-looking companion to [`vision.md`](./vision.md). Vision locks the **architecture** OSPlus is built on; this doc tracks the **features** built on top.

If you're an agent picking up work: this is where you find what's coming, what's deferred, and what hasn't been thought through enough yet. It is not a task tracker — no estimates, no dates, no checkboxes.

## How to read this doc

| Section | What it means |
|---|---|
| **Now** | Actively being worked on. Usually one thing. |
| **Next** | Known features whose *what* is defined but whose *how* (and therefore inter-dependencies) is not yet pinned down. **Order is not implied** — engine/UE limitations we're still discovering may force re-sequencing as we learn. |
| **Later** | Named wants whose *what* itself isn't fully defined yet. Parking lot, not a queue. |
| **Open questions** | Feature-level decisions that need a conversation before the feature can move from Later → Next. (Architectural open questions live in `vision.md`'s `[TBD]` section.) |
| **Won't do for v1 (and why)** | Things that *feel* obvious to add but have been explicitly deferred. Cheaper than re-litigating each time. |

**Maintenance rule:** anything sitting in **Later** for 6+ months unmoved should either get promoted to **Next**, demoted to **Won't do**, or deleted. Staleness is the failure mode of roadmaps.

---

## Now

**Agentic workflow buildout** — the docs/rules/skills scaffolding that makes future feature work compoundable instead of repetitive. Tracked across phases; this doc itself is Phase 5. One phase remaining (Phase 6: split `KNOWLEDGEBASE.md` into `docs/architecture/`, `docs/engine/`, `docs/re/`).

Once Phase 6 wraps, the next active item is presumed to be the `feat/chat-presence-and-colors` work named in `vision.md` § Status — but that's a fresh decision when we get there, not pre-committed here.

## Next

> Reminder: order in this section is **not** a priority queue. Each item's *what* is defined; the *how* (and therefore which one is cheapest to do first) depends on engine reality we're still mapping.

### Profile module v1
- **What:** Stand up `server/profile/` as a REST module inside the relay process. Identity-only schema (`steamId`, `displayName`, timestamps). SQLite on the relay VM.
- **Why now:** Locked in `vision.md` Locks 2 + 3. Every feature below either reads from it or writes to it.
- **Acceptance hint:** A relay restart preserves profile rows. A handshake from a fresh sidecar creates a row. A handshake from a returning sidecar updates `displayName` and `updatedAt`.

### Chat presence indicator
- **What:** Show, in the chat UI, who is currently connected to the chat room. Late joiners see the existing roster, not just future join events.
- **Why now:** Directly requested. Also the canonical worked example for `vision.md` Lock 4 (ephemeral state on the relay; clients re-handshake on reconnect).
- **Open question that gates this:** *Presence scope* — see Open questions below.

### Per-player chat name colors
- **What:** Each player's chat messages render in a stable color, so a player can visually parse the chat at a glance.
- **Why now:** Directly requested.
- **Out of scope for this feature:** color customization or persistence — those are explicitly **Won't do for v1** below.
- **Open question that gates this:** *Color allocation method* — see Open questions below.

## Later

(Sparse on purpose — items land here when named, not pre-invented.)

- _(none yet — populated as wants surface in conversation)_

## Open questions

These are **feature-level** questions. Architecture-level open questions live in [`vision.md`](./vision.md) § Open questions and are referenced where relevant.

- **Presence scope.** Is "presence" defined as *in the chat room*, *in the game (any state)*, or *in a match*? These imply different broadcast triggers and different correctness rules. (Gates: Chat presence indicator.)
- **Color allocation method.** Deterministic from `steamId` (hash → palette), random-but-sticky-per-session, or assigned by the server on first connect and persisted? The first is implementation-only; the third forces a profile schema growth (Lock 3 process). (Gates: Per-player chat name colors. Forces a conversation that touches `vision.md` Lock 3 if we go server-assigned.)
- **Channel/room model.** Single global chat room, per-match room, or both? Today there's one room. Adding more is cheap to imagine, expensive to retrofit if we got the addressing model wrong. (Gates: anything that wants to scope a message to a subset of players.)
- **Scrollback policy.** `vision.md` Lock 4 defaults to "no persistence." Does any feature force an opt-out? (Gates: any "I joined late, what did I miss" expectation beyond the current session.)

## Won't do for v1 (and why)

- **Color picker UI / persisted user-chosen colors.** Explicitly deferred — the player getting to pick their name color is the lowest-impact thing this platform could ship and doesn't justify the storage/UI/sync surface yet. Reconsider once the profile module exists and there's a real reason to put a setting in it.
- **Verified SteamID auth.** `vision.md` Lock 1 commits to trust-on-claim by design. Don't ship features whose security model assumes authenticity (currency, trading, moderation) until that lock is revisited.
- **Persistent chat history.** `vision.md` Lock 4 defaults to ephemeral. No feature has named a reason to opt out. Reconsider when one does — and use the lock's "deliberate per-feature decision" carve-out, not a quiet drift.
- **Public distribution channel beyond Drive direct link.** Currently a single Drive link is the distribution mechanism (see `release-checklist` skill, Phase 5). Picking a real channel (GitHub Releases, NexusMods, etc.) is deferred until there's a reason to widen the audience.
