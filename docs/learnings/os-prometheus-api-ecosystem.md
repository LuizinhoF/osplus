# os-prometheus-api-ecosystem

| Field | Value |
|---|---|
| Date | 2026-04-24 |
| Area | re |
| Tags | prometheus, os-backend, trackers, identity, external-api |
| Status | confirmed |

## Symptom

Designing OSPlus's in-game profile MVP required answering "what data does the Omega Strikers backend already expose externally vs. what has to be observed locally from the client?" — the answer determines what's worth capturing in OSPlus vs. what's already available from aggregate tracker sites. Cold-researching this from scratch was at risk of eating 2–4 hours per session any time a future feature re-asked the same question.

## Root cause

No canonical documentation of Omega Strikers' backend exists, because Odyssey hasn't published one. All the knowledge is distributed across community tracker sites and their partially-published source code. This isn't broken — it's just undiscovered, and the cost of re-deriving it is non-trivial.

## Fix

Mapped the ecosystem once and promoted the findings to `KNOWLEDGEBASE.md` (new "Backend Ecosystem — Odyssey's Prometheus API" section under *Omega Strikers — Game Internals*, plus an expanded "Player Identity Reference" with the three-identifier table). Key facts that now live in KB:

- **Odyssey runs an undocumented backend API.** The community calls it "Prometheus" because the game's own `Prometheus` UE module name leaks into schema/ID naming (e.g. `PMPlayerPublicProfile.PlayerId` is the same hex string the backend + trackers use as canonical player key).
- **Every OS tracker in the wild taps the same API.** [stats.omegastrikers.gg](https://stats.omegastrikers.gg/), [clarioncorp.net](https://clarioncorp.net/), [strikr.gg](https://strikr.gg/), [omegastrikers.stlr.cx](https://omegastrikers.stlr.cx/) — different UIs, one upstream. [Clarion](https://docs.clarioncorp.net/) has the most public documentation of what Prometheus exposes.
- **Auth** is a JWT pair (`ODYSSEY_TOKEN` / `ODYSSEY_REFRESH_TOKEN`), obtainable via Fiddler Classic live capture or a Steam-Ticket → Odyssey auth handshake (per Clarion; full guide not yet published).
- **Grey-zone community posture.** One known case of an NDA after reverse-engineering (Strikr-GG); no broader prosecution. OSPlus should assume the same posture applies if it ever calls Prometheus directly.

**The capture gap — canonical statement for future features:** Prometheus exposes player metadata, per-character aggregates (games/wins/losses/mvp/knockouts/assists/saves/scores per character × role × gamemode), season ratings, mastery totals, and per-match metadata (map, score, duration, timestamp, rank deltas). It does **not** expose redirects, per-match event sequences (who scored when), in-match transient state, or anything the backend doesn't persist. When OSPlus finds itself asking "can we just get this from a tracker?", the answer is almost always "no if it's per-match event granularity, yes if it's a career aggregate."

**Three-identifier clarification** (folded into the KB's Player Identity Reference):
- **SteamID** (17-digit decimal) — from `PMIdentitySubsystem`. OSPlus already resolves this.
- **Prometheus ID** (24-char hex / MongoDB ObjectID) — backend canonical key. Every tracker uses this, not SteamID. OSPlus does **not** currently surface this.
- **Display name** — user-mutable; already handled via the three-mode resolver in `identity.lua`.

## Lesson

For any OSPlus feature that asks "is this data server-side available?" the answer lives in the Clarion docs and/or the cross-tracker capture gap. When none of the trackers display something, it's usually because the Prometheus API doesn't expose it — redirects being the canonical example. That gap is OSPlus's capture target: anything the client observes but the backend doesn't persist.

When identity design is in play, **three identifiers matter, not two** — choose deliberately. Binding an OSPlus profile on SteamID is simple but doesn't interoperate with tracker data; binding on Prometheus ID interoperates but requires unlocking a path the game doesn't expose cleanly from Lua today (see `PMPlayerModel` UFunction-signature note in KB).

## Related

- Feature: `docs/features/in-game-profile-mvp.md` (Feasibility Pass 1 — this learning is its byproduct)
- KB: `KNOWLEDGEBASE.md` → *Omega Strikers — Game Internals* → *Backend Ecosystem — Odyssey's "Prometheus" API* and *Known Unknowns → Player Identity Reference*
- Prior learnings (the three-mode `PlayerNamePrivate` story):
  - `docs/learnings/playernameprivate-transient-account-id.md`
  - `docs/learnings/playernameprivate-machine-name-out-of-match.md`
- External sources:
  - [docs.clarioncorp.net](https://docs.clarioncorp.net/) — Clarion's public v2 API + Prometheus proxy docs (the most complete publicly-available description of the upstream surface)
  - [github.com/ClarionCorp](https://github.com/ClarionCorp) — Clarion's published code
  - [github.com/Strikr-gg/strikr-api](https://github.com/Strikr-gg/strikr-api) — README candidly describes auth shape + the NDA situation
  - [github.com/ckhawks/omega-strikers-tracker](https://github.com/ckhawks/omega-strikers-tracker) — another community tool; per-match drill-down UI
