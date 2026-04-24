# OSPlus — Roadmap

Forward-looking companion to [`docs/product.md`](./product.md) (the product north star) and [`docs/decisions/`](./decisions/) (architectural deliberations). Product defines *why* and *for whom*; decisions lock *how*; this doc tracks the *features* built on top.

If you're an agent picking up work: this is where you find what's coming, what's deferred, and what's been explicitly dropped for not serving the wedge. Not a task tracker — no estimates, no dates, no checkboxes.

## How to read this doc

| Section | What it means |
|---|---|
| **Now** | Actively being worked on. Usually one thing. |
| **Next** | Known features whose *what* is defined but whose *how* is not yet pinned down. **Order is not implied** — engine/UE limitations we're still mapping may force re-sequencing. |
| **Later** | Named wants whose *what* itself isn't fully defined. Parking lot, not a queue. |
| **Needs ADR before it can move** | Features that force an architectural decision currently pending in `docs/decisions/`. They cannot ship — even as prototypes — until the relevant ADR is accepted. |
| **Open questions** | Feature-level decisions that need a conversation before the feature can move from Later → Next. |
| **Won't do for v1 (and why)** | Things that *feel* obvious to add but have been explicitly deferred. Cheaper than re-litigating each time. |

**Product filter — every item on this roadmap answers yes to all three:**

1. Does it reinforce retention of non-veteran players?
2. Does it avoid cheat territory and ToS-adversarial amplification?
3. Can it survive the next Odyssey patch with zero work?

If a proposed feature doesn't pass all three, it belongs below in "Won't do" with a one-line reason.

**Maintenance rule:** anything sitting in **Later** for 6+ months unmoved should either get promoted, demoted to **Won't do**, or deleted. Staleness is the failure mode of roadmaps.

---

## Now

**Agentic workflow foundation rebuild.** Replacing the prior `vision.md` architectural locks with `docs/product.md` (product definition) + ADR discipline (`docs/decisions/`). Currently Phase 5 (reconciling downstream docs) — this file, `AGENTS.md`, and `feature-design` skill. Phase 6 (cold-start validation against new docs) remains.

Once the foundation pass wraps, the next active feature-level item is a decision point: pick the first piece of the wedge (profile scaffolding vs. first unlockable-earning path), which will force the identity ADR.

## Next

> Reminder: order is **not** a priority queue. Each item's *what* is defined; the *how* — and therefore which is cheapest to do first — depends on engine reality we're still mapping.

### In-game profile scaffolding — v1 of the wedge

- **What:** a minimal in-game profile surface showing stats the game API doesn't expose (redirects, per-character data), plus one visible unlockable slot (badge/title/flair) that later features populate.
- **Why:** the wedge. Without this, nothing else in the engagement loop can hang off anything. Directly serves `docs/product.md` → wedge.
- **Forces ADR:** **identity model** (trust-on-claim SteamID is the archived position; community events with earned credit make it re-decidable). Cannot ship until that ADR is accepted.
- **Forces ADR:** **profile storage architecture** — persistence of profile rows across restarts requires committing to the storage approach.
- **Acceptance hint:** player opens the in-game profile panel and sees their current values for two game-derived stats that no tracker site exposes. One unlockable slot renders empty for a player with no unlockables.

### First unlockable-earning path

- **What:** ship one concrete way to earn one cosmetic (badge). Could be a stat threshold ("win 5 matches as X character") or an event participation flag. Pick the cheapest one that demonstrates the loop.
- **Why:** validates that the wedge actually retains — players earn something, they see it, a friend notices, the loop holds. Without shipping even one of these, the wedge is theoretical.
- **Forces ADR:** depends on path chosen. Stat-threshold needs a stats-ingestion pipeline. Event-participation needs an event-definition surface and identity (because crediting needs a trusted player identity).

### Community event — end-to-end proof of cadence

- **What:** run one curator-led event end-to-end. Announce → players participate → earn → cosmetic is visible in profile. Scope small intentionally.
- **Why:** the content-cadence half of the wedge. Profile without events = stats tracker. Profile with events = content cadence OS doesn't get from Odyssey.
- **Forces ADR:** **ephemeral state ownership** (event state — participants, deadlines, pending credits — is exactly the shape of thing the archived Lock 4 covered, which is now open for deliberation).

## Later

(Sparse on purpose — items land here when named.)

- **Queue intelligence / "is anyone playing right now?"** — the funnel half of the retention problem. Defined in `docs/product.md` → long-horizon shape as v2 priority. Deferred explicitly because (a) it requires a signal source that needs investigation (sidecars reporting? external scraping?), and (b) the wedge is the engagement loop, not the funnel.
- **Community-submitted cosmetics** — scoped-up version of the events model where players submit assets. Deferred because moderation, IP risk, and asset pipeline are all large scope. Revisit after v1 curator-led events validate the cadence.

## Needs ADR before it can move

Items here have a defined *what* but cannot progress until the named ADR is accepted. See `docs/decisions/README.md` → "First-priority deliberation queue."

| Feature | Forces ADR on | Why |
|---|---|---|
| In-game profile scaffolding | Identity model | Profile rows need a stable identifier with an explicit trust posture. |
| In-game profile scaffolding | Profile storage | Persistence across restarts requires committing to storage architecture. |
| Community event (end-to-end) | Ephemeral state | Event state is the canonical example of shared short-lived data. |
| Chat presence indicator (if revived) | Ephemeral state | Same shape as events, previously covered by archived Lock 4. |

## Open questions

Feature-level questions that need a conversation before promotion to Next. (ADR-level questions are tracked in `docs/decisions/`.)

- **Unlockable-earning vector mix.** Ratio of achievement-earned vs. event-earned vs. participation-earned cosmetics — should there be all three, or does v1 pick one to test?
- **Profile visibility defaults.** Is the profile panel self-view only at v1, or can players view each other's? Viewer-mode forces identity-display decisions and potentially privacy defaults.
- **Event cadence sustainability.** Events require curator time. What's the minimum viable cadence where "one event per month" is acceptable and still testable as a loop?

## Won't do for v1 (and why)

Per `docs/product.md` anti-goals + the three-filter test above:

- **Cheat-adjacent features.** Opponent stat lookups during match, in-match build recommenders, custom HUDs exposing hidden info, predictive ELO. Fails filter 2.
- **Monetization of any kind.** Paid cosmetics, Patreon perks, ads. Product-level NO, not a roadmap reconsideration.
- **NSFW/NSFL content.** Product-level NO.
- **Cross-game anything.** Product-level NO.
- **Replacing native game UI wholesale.** Additive surfaces only; targeted menu replacement requires an ADR and is defaulted to no.
- **Color picker UI / user-chosen name colors, standalone.** Doesn't serve the wedge. Could live inside the unlockables model later (earned color slots), but not as a standalone v1 feature.
- **Verified SteamID auth as a prerequisite.** Held in the identity ADR queue; won't block v1 work but won't be assumed present either.
- **Persistent chat history.** Chat is infra, not product. No feature has named a retention reason.
- **Public distribution channel beyond Drive direct link.** Deferred until there's a reason to widen audience beyond the SA-community distribution surface.
- **Features aimed primarily at streamers or veterans.** In-scope long-tail per `docs/product.md`, not a v1 design driver. "It'd be cool for streamers" alone doesn't promote anything from Later.
- **Generalized fun / silly features with no retention story.** "Fun reinforces retention" is the test; "fun in isolation" is not.
