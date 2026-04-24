# OSPlus — Product

*"Odyssey won't update Omega Strikers? Ok, OSPlus will."*

OSPlus is a community-maintained mod layer that keeps Omega Strikers alive for the people still playing it — turning a maintenance-mode game into a place with things to work toward, events to participate in, and a reason to keep the client installed.

## Audience

**Primary:** non-veteran OS players. Newcomers who want smoother onboarding + mid-skill players who want something to grind toward beyond competitive rank. Solving their friction increases the overall active population, which indirectly addresses the veterans' "no one to play with" complaint.

**Distribution context:** v1 launches into a **~25-player friend-adjacent South American community** where the maintainer is known and trusted. Broader OS community is the ambition, not the v1 reality. This matters: the cost of several architectural compromises is far lower at friend-group scale than at public-mod scale.

**Not the audience (but benefit incidentally):** content creators/streamers, pro/ranked-grinder veterans. Explicitly in-scope as long-tail but never as design drivers.

## Problem

OS is in maintenance mode — Odyssey ships map rotations and number tweaks, nothing else. The player-side damage is "death by a thousand cuts," three of which cluster into addressable problems:

1. **Empty-queue friction.** Queues fire only at specific late hours. Players try to play, find no one, leave frustrated. Nothing today tells them when it's worth queueing.
2. **No alt-progression.** Competitive rank is the *only* progression vector. Players without ladder ambition have nothing to work toward.
3. **Onboarding cliff.** "Low-skill" in the OS community means "veteran with bad mechanics." Newcomers get stomped and have no way to situate themselves.

Existing tracker sites show match history and win-rates but (a) can't capture redirects or per-character stats because the game API doesn't expose them, (b) require alt-tabbing out, and (c) most players don't know they exist.

## Wedge + long-horizon shape

**v1 wedge:** **in-game profile + unlockables, fed by community events.**

- **Profile** surfaces stats *in-game* that external tracker sites can't get at (redirects, per-character data) via runtime observation of game state.
- **Unlockables** are OSPlus-internal cosmetics — badges, titles, profile flair — earned through in-game achievements and event participation. No cosmetic ships untethered from the engagement loop; "free-for-all" cosmetics still require event participation.
- **Events** are the content cadence that Odyssey isn't shipping. Curator-led at v1. They double as the thing players can interact with when queues are empty, addressing problem #1 as a side-effect of the engagement loop.

**Chat is infrastructure, not product.** Already shipped. It validated the sidecar+relay+pak+install pipeline, which is now paid-forward for the wedge. It remains useful as a side feature but no longer drives roadmap focus.

**Long-horizon shape:** OSPlus becomes the substrate that other in-game layers plug into — queue intelligence (v2 priority, attacks problem #1 directly with a signal source), richer event tooling, and eventually community-submitted content pipelines. The core bet: if players keep OSPlus installed for the wedge, every future layer gets distribution for free.

## Anti-goals

OSPlus explicitly does NOT:

- **Cheat-adjacent anything.** Opponent stat lookups during match, in-match build recommenders, HUDs exposing hidden information, predictive ELO. Amplifies ToS risk and corrupts the product.
- **Monetize.** No paid cosmetics, no Patreon perks, no ads. Ever.
- **Carry NSFW/NSFL content.** Mod follows the base-game audience rating.
- **Ship pure silliness / caricature content.** Fun that reinforces retention is fine; meme-maxxing that turns OSPlus into a joke is not.
- **Cross-game.** OSPlus is OS-only.
- **Replace native game UI wholesale.** Additive surfaces are the default. Targeted menu replacement is case-by-case and requires an ADR — it fights the (unlikely but non-zero) possibility of Odyssey ever shipping a UI update.
- **Assume Odyssey cooperation.** No features that depend on an official API, partnership, or ToS waiver.

**In-scope but explicitly long-tail (not v1 design drivers):**

- Streaming/creator features — justified as organic-distribution amplification, not as serving a primary audience.
- In-depth analytics / performance grading — valuable eventually; foundational work first.

**Three filters every feature passes through:**

1. Does it reinforce retention?
2. Does it cross into cheat territory?
3. Would it survive the next Odyssey patch with zero work?

## Success

**Signal-based, not metric-based.** The community is too small for numbers to mean anything — one person's opinion is ~4-5% of the primary audience. Measurement infrastructure would cost more than it would teach us.

**6-month signals:**
- Profile + unlockables shipped.
- At least one complete event cycle end-to-end.
- Recognizable usage within the SA active playerbase.
- Unprompted OSPlus mentions in community channels.
- Returning/lapsed players cite OSPlus as a reason to re-queue.

**1-year signals:**
- Engagement loop is self-sustaining enough that skipping a month wouldn't kill it.
- Community recognizes OSPlus as *the* definitive layer on OS, not an experiment.
- Community-driven event proposals arrive unprompted.

**Honest failure modes (define failure explicitly, not just success):**
- **Personal:** maintainer stops enjoying OS itself. If you don't play, you don't build.
- **Capacity:** maintenance effort exceeds sustainable time budget.
- **Economic:** infra costs grow faster than engagement signal justifies.

## Hard constraints

**Verified immovable:**

| Constraint | Why |
|---|---|
| UE 5.1.0 runtime exactly | Cook schema mismatches corrupt complex widgets |
| `DefaultEngine.ini`: `CanUseUnversionedPropertySerialization=False` | ScrollBox + other complex widgets deserialization crash |
| BPModLoaderMod: `ModActor` hardcoded at `/Game/Mods/OSPlus/ModActor` | Renaming breaks loading |
| ToS-adversarial posture | Accepted risk; not negotiable if OSPlus ships |
| No NSFW/NSFL | Follows base-game audience rating |

**Strong current assumptions — unverified; treat as current-implementation, not locked architecture:**

- UE4SS Lua networking absence (forces sidecar+file-IPC topology). If proven false under inspection, the sidecar topology becomes re-examinable.
- No Steamworks API access.
- DX11/SM5-only renderer; no Lumen / virtual shadow maps / mesh distance fields.

**Operational:**

- Single maintainer for the foreseeable future (not hard; not assumed forever).
- Free-tier infrastructure budget (OCI VM, DuckDNS). Infra migration is acceptable; re-architecting isn't.
- Maintainer must still enjoy OS itself.

## Current architectural choices under re-examination

The prior `docs/vision.md` encoded four "v1 locks" without deliberation. That approach has been superseded. Three of the four are flagged as **first-priority ADR work** — they carry architectural consequences that compound if deferred:

| Current choice | Status | Forcing consideration |
|---|---|---|
| Identity = trust-on-claim SteamID | **Needs ADR.** | Community events with earned credit make spoofing a real problem. |
| Profile storage = in-process SQLite + single OCI VM | **Needs ADR.** | Fine at ~25; escape-hatch "extract later" is the kind of work that never happens if not deliberated. |
| Ephemeral state = in-memory on relay | **Needs ADR.** | Same scaling shape as above. |
| Schema grows on demand | **Kept as policy.** | Not an architectural lock, just how we work. No ADR needed. |

See [`docs/decisions/`](./decisions/) for active deliberations and [`docs/decisions/_archive/vision-v1-superseded.md`](./decisions/_archive/vision-v1-superseded.md) for what this replaces and why.

## What this document is for

Read it at the start of a fresh session. Read it before designing a feature. Read it before arguing for a new direction. If a proposed change doesn't fit the audience, the problem, the wedge, or the anti-goals, it doesn't belong in v1 — surface the conflict instead of quietly expanding scope.
