# Gear

Pre-match passive tuning that nudges a Striker's role/style.
Frequently confused with "the build" — *gear is not the build*.
Gear is one of three layers (kit / gear / Awakenings) that combine
to define how a Striker plays in a given match.

> **Status:** seeded 2026-05-01 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 16.
>
> **Last validated against game patch:** 2026-04. Specific gear
> options and their stat lines are patch-volatile. The
> *abstraction* (gear is pre-match passive tuning, not a full
> build system) is mechanically stable. Re-validate when patch
> notes mention gear, gear slots, gear progression, or gear-related
> Awakening interactions.

This doc is the player-side conceptual layer. The engine-side
representation of gear is **not catalogued** in this docset and is
surfaced as a TBD in [Open questions](#open-questions). Gear is the
least-investigated of the three build layers in OSPlus today.

## TL;DR

- **Gear is a pre-match passive choice.** Selected during
  [striker-select](./striker-select.md), applied for the whole
  match, no in-match modification.
- **Gear is NOT a build editor.** It's *one slot* (or a small
  number of slots — the exact count is **TBD**) of role/style
  tuning, not a deep itemization system.
- **Gear is the lightest of the three build layers.** The full
  picture is: Striker kit (base identity) + Gear (pre-match
  tuning) + Awakenings (in-match evolution). Gear sits between
  the others in commitment depth.
- **Gear is the easiest layer to over-promise.** Beta-era OS had
  a more substantial pre-match build system; talking about gear
  as if it's still that system mis-frames the current game.

## The three build layers (preserved from source)

The source doc Sec 16 framed gear with this useful three-layer
mental model. Preserved verbatim because it's the cleanest summary
of how the *full* OS build system actually works:

```text
Striker kit         = base identity
Gear                = pre-match role/style tuning
Awakenings          = in-match build evolution
Map                 = environmental constraint
Team composition    = strategic context
Enemy composition   = counterplay context
```

Reading this:

- **Striker kit** is what you can't change after the match starts.
  See [`strikers-and-abilities.md`](./strikers-and-abilities.md).
- **Gear** is what you commit to before the match. **This doc.**
- **Awakenings** are what you commit to inside the match. See
  [`awakenings.md`](./awakenings.md).
- **Map / team comp / enemy comp** are not choices the player
  makes — they're context the choices respond to. See
  [`maps.md`](./maps.md), [`roles.md`](./roles.md).

The three *player-controlled* layers (kit / gear / Awakenings)
combine to form the actual playable identity for a given match.

## What gear actually is (player perspective)

| Observation | Detail |
|---|---|
| **Pre-match commitment.** | Selected during striker-select; applies for the whole match. |
| **Passive effects.** | Gear modifies stats / behavior continuously rather than via active inputs. No "use gear" button. |
| **Role/style oriented.** | Gear options nudge a Striker toward a specific way of playing — e.g., more goalie-leaning, more aggressive, more cooldown-heavy. |
| **Carries between matches.** | Once chosen, the gear preference persists until the player changes it. Different matches can use different gear. |
| **Patch-volatile catalog.** | Specific gear options and stat lines move with seasons. **Per-gear matrix is not catalogued in this doc — would age out fast.** |

What gear is *not*:

- **Not** an item shop (no in-match purchase).
- **Not** a rune page / talent tree (no per-match deep
  customization).
- **Not** a loadout planner (typically just one slot, or a small
  number — see [Open questions](#open-questions)).
- **Not** an Awakening replacement (gear locks in pre-match;
  Awakenings draft in-match — different commitment depths).

## Why gear is the lightest layer

Gear is intentionally narrower than Awakenings:

- **Awakenings respond to the match in flight** (you draft based
  on what's happening). Gear does not — it's frozen at match
  start.
- **Awakenings have multiple draft moments.** Gear has one (the
  pre-match selection).
- **Awakenings can radically reshape a kit.** Gear nudges a kit;
  it doesn't reshape it.

The design intent (per Sec 16) is that gear gives the player a
*directional* commitment — "I'm going to play this Striker
defensively today" — without locking them into a deterministic
build path. The Awakening drafts then give them the in-match
flexibility to adapt that directional commitment.

## Where OSPlus could attach

Gear is a moderate-leverage feature surface, but the patch-
volatility ceiling on the catalog limits the depth a feature can
reasonably go.

**Likely good feature shapes:**

- **Per-Striker gear-fit notes.** "If you're playing X Striker as
  goalie, Y gear is a common pick." Information surfacing without
  prescription.
- **Post-match gear retrospective.** "You picked X gear; here's
  how it correlated with your performance over the last N
  matches." Lives in [`post-match.md`](./post-match.md) territory
  more than here.
- **Gear-loadout helpers.** "Save / load gear preferences per
  Striker so you don't have to re-pick every time."
- **Gear catalog references.** A patch-aware lookup that surfaces
  current gear stat lines without forcing the player into the
  game's gear menu mid-flow.

**Likely bad feature shapes:**

- A "build editor" that frames gear as part of a deep
  itemization system. (See the warning in
  [`awakenings.md` → "OSPlus framing rules"](./awakenings.md#osplus-framing-rules)
  — gear is *adjacent* to that framing trap.)
- Hard-coded per-gear matrices in the OSPlus codebase. **Patch-
  volatile data should live in JSON / config, not in code.**
- Gear-related auto-pick features that take agency away.
- Mod-side new gear (not what OSPlus is for).

## Engine bridge (one-link summary)

Gear-related engine names are **NOT catalogued** in this docset.
Search candidates from a fresh probe:

- **Gear definition class.** Likely under `/Script/Prometheus.*`
  with `Gear` in the name. **TBD.**
- **Per-player equipped gear.** Likely on `MeResponseV1` /
  `PMPlayerPublicProfile` (alongside the cosmetic loadout slots
  documented in [glossary → "Cosmetic loadout"](../glossary.md#cosmetic-loadout)).
  Note that gear is a *gameplay-affecting* commitment whereas
  the cosmetic loadout is purely visual; the engine likely
  separates them. **TBD.**
- **Gear UI widget.** Likely under `WBP_*Gear*` or surfaces inside
  the [striker-select widget](./striker-select.md#engine-bridge-one-link-summary).
  **TBD.**

Per ADR 0003, engine search-target lists do not live in this
player-side doc.

## Open questions

- **How many gear slots exist?** Player observation: appears to be
  one or a small number (not, e.g., a six-slot itemization).
  Specific count **TBD.**
- **Gear catalog (per-patch).** What gear options exist this
  season, what each does, what the stat ranges are. **Patch-
  volatile; not catalogued in this docset.**
- **Gear progression / unlock model.** Is gear unlocked by playing,
  earned via progression tracks, purchased? **TBD.**
- **Per-Striker gear restrictions.** Whether all gear is available
  to all Strikers, or some are kit-specific. **TBD.**
- **Awakening × gear interactions.** Whether some Awakenings
  amplify specific gear choices (likely, given how interconnected
  the build layers are). Patch-volatile. **TBD; out of scope for
  this doc.**
- **Engine class cluster.** Gear definition class, per-player
  equipped gear field, gear UI widget — see
  [Engine bridge](#engine-bridge-one-link-summary). All **TBD.**

## Cross-references

- The other two build layers: [`strikers-and-abilities.md`](./strikers-and-abilities.md), [`awakenings.md`](./awakenings.md)
- Where gear gets selected: [`striker-select.md`](./striker-select.md)
- Where gear gets retrospectively reviewed: [`post-match.md`](./post-match.md)
- Map context that shapes gear viability: [`maps.md`](./maps.md)
- Roles that gear biases toward: [`roles.md`](./roles.md)
- Engine bridge for the cosmetic-loadout cluster gear may sit alongside: [glossary → "Cosmetic loadout"](../glossary.md#cosmetic-loadout)
- Sibling docs index: [`docs/game/README.md`](./README.md)
