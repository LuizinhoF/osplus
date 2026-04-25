# ADR 0001 — Bind OSPlus profiles to the Odyssey (Prometheus) account ID

| Field | Value |
|---|---|
| Status | `accepted` |
| Date | 2026-04-24 (proposed) → 2026-04-25 (accepted post-Pass-4 spike) |
| Forcing feature | `feat/in-game-profile-mvp` (Stage 3 / Feasibility complete; Stage 4 unblocked by this ADR) |
| Supersedes | `docs/decisions/_archive/vision-v1-superseded.md` → Lock 1 (claimed SteamID) |
| Superseded by | — |

## Context

OSPlus today binds profile rows to **claimed SteamID** (per `_archive/vision-v1-superseded.md` → Lock 1, archived 2026-04-23 along with the rest of the vision doc). The `in-game-profile-mvp` feature is the first to actually require a persistent profile row, which is what forces this decision now.

Two new constraints reshape the options space relative to the archived position:

1. **Maintainer requirement: platform-agnostic.** Omega Strikers may be playable from launchers other than Steam (Epic, Discord, future console ports, GeForce Now). SteamID is platform-specific by construction; binding the canonical profile row to it forecloses non-Steam players. The archived position implicitly assumed Steam-only and didn't name this.
2. **Tracker-ecosystem interop is a real future requirement, not hypothetical.** Every Omega Strikers tracker (`stats.omegastrikers.gg`, `clarioncorp.net`, `strikr.gg`, `omegastrikers.stlr.cx`) keys off the Odyssey backend's "Prometheus ID" — a 24-char hex MongoDB ObjectID — *not* SteamID. An OSPlus profile keyed on SteamID cannot join its own captures (e.g., per-match redirects from `in-game-profile-mvp`'s capture surface) against tracker-ecosystem aggregate stats without doing Prometheus-ID resolution anyway. See `docs/learnings/os-prometheus-api-ecosystem.md` and KB → *Player Identity Reference*.

Pass 3 of the in-game-profile-mvp feasibility (committed in this branch) characterized the runtime path to the local Prometheus ID end-to-end. The runtime data model is documented in `docs/learnings/os-runtime-data-model.md`. The path that was previously thought to be blocked ("`PMPlayerModel` UFunctions are not trivially callable from Lua") turned out to be a calling-convention misunderstanding — the call shape is now known. **The decision is no longer blocked by feasibility; it is blocked only on this ADR.**

## Options considered

Three independent sub-decisions are bundled in this ADR because they share a single forcing feature:

- **(P)** Primary binding key — what column is the row's identity?
- **(R)** Resolution path — how do we get that identity from the running client?
- **(T)** Trust posture — do we verify the claim, or trust it as-reported?

P and R are presented as independent options below. T is a separate section because both posture options apply on top of any P/R combination.

### Primary binding key — Options

#### P-A — Trust-on-claim SteamID (archived position)

- **What it is** — Profile row keyed on `steamId TEXT PRIMARY KEY` (17-digit decimal). Sidecar reads `PMIdentitySubsystem:GetSteamId()` (already implemented in `identity.lua`); claims it to the relay at handshake; relay trusts the claim.
- **Pros** — ~Zero implementation cost (already partially built). Stable per-player, cross-session.
- **Cons** — **Steam-only by construction.** Non-Steam launches either can't have a profile or get a synthetic fallback that has to be reconciled later. Cross-tracker interop blocked unless we *also* resolve the Prometheus ID — i.e., doing this work later instead of now. Schema migration from `steamId`-keyed rows to a different primary key later is high-cost (cascading FK rewrites).
- **Cost to build** — Near zero.
- **Cost to change later** — High. Migrating a user base off this key requires either resolving Prometheus IDs at migration time (the same work this ADR is asking us to do now) or accepting a discontinuity in profile history.

#### P-B — Prometheus ID

- **What it is** — Profile row keyed on `prometheusId TEXT PRIMARY KEY` (24-char hex). SteamID retained as a secondary indexed column (`steamId TEXT NULL` — null for non-Steam players).
- **Pros** — Platform-agnostic (the requirement that rules out P-A). Aligns with the tracker ecosystem's keying convention, so cross-tracker enrichment becomes a possibility rather than a port. Resolves a constraint we know will eventually bite (non-Steam OS launches) before any user-visible feature is built on the wrong key.
- **Cons** — Requires resolution-path work (see R-options below). Requires the runtime data path that was previously thought blocked (now unblocked per Pass 3 / `os-runtime-data-model.md`). Adds one column over P-A's schema.
- **Cost to build** — Small. Identity-resolution path is now characterized; ~50 lines of Lua + schema additions.
- **Cost to change later** — Low. SteamID retained as secondary, so cross-references stay reachable; switching primary key away from Prometheus ID is unlikely (the only other candidate is SteamID, which P-A rejects).

#### P-C — Composite key (Prometheus ID + SteamID + per-install UUID)

- **What it is** — No single primary key; row identity is the tuple. Each profile row carries any subset of the three available identifiers.
- **Pros** — Maximally flexible. Future identifiers (Epic ID, console IDs) bolt on without schema migration.
- **Cons** — Foreign-key shape ambiguous from day one — every dependent feature has to choose which column to FK against. Profile-row uniqueness becomes a definitional question (two rows with overlapping but non-identical tuples — same player or not?). Premature flexibility for a problem that doesn't exist yet (only Steam launches are observed in the field today).
- **Cost to build** — Medium. Schema design plus uniqueness-rule design plus FK guidance.
- **Cost to change later** — Lowest of the three (it's already flexible) — but the cost of *living with the complexity* every day is high.

### Resolution path — Options (assume binding-key Option P-B)

#### R-A — Synchronous polling

- **What it is** — `identity.lua` polls `FindFirstOf("PMPlayerModel"):GetCachedMeResponseV1(false, nil)` on each tick. The call returns `(WasCached: Bool, MeResponse: MeResponseV1)`. `MeResponseV1` extends `PlayerPublicProfile` (UE `ScriptStruct` `sps` inheritance), so `MeResponse.PlayerId` is the Prometheus ID. Once `WasCached == true`, cache the result, stop polling, emit the identity event.
- **Pros** — Conceptually simplest. Single call, single source of truth.
- **Cons** — If the local PMPlayerModel cache hasn't filled by the time the script starts polling, `WasCached == false` indefinitely (no upper bound on wait). **Plus a build-blocker discovered in the Pass-4 spike:** UE4SS in this build cannot call `GetCachedMeResponseV1` (or any other `(Bool out, X out)` UFunction on `PMPlayerModel`) from Lua at all — every documented placeholder shape errors at the marshaling layer. To make R-A work in this build the call would have to go through a BP wrapper (same substrate cost R-B pays), reducing R-A's "simplest" advantage to effectively zero. See `docs/learnings/ue4ss-outparam-marshaling-failure.md`.
- **Cost to build** — Was: small. Revised: same as R-B's BP-wrapper cost + a poll loop (i.e., R-B's cost minus the reactive primitive's value).
- **Cost to change later** — Low — internal to `identity.lua`.

#### R-B — Event-driven (multicast delegate via ModActor BP wrapper)

- **What it is** — Subscribe to `PMPlayerModel.GetMeRequestV1Completed` — a `MulticastInlineDelegateProperty` on `PMPlayerModel`, typed by signature `MeRequestV1Completed__DelegateSignature`. (Equivalent property `GetDisplayNameV1Completed` exists for display-name fetches.) Per the Pass-4 spike (see *Discovery output* below), UE4SS's `prop:Add` takes `(UObject, FName)` — *not* a Lua function — so the binding target is a Blueprint actor delivered via `BPModLoaderMod` (the existing `mod-actor-pattern.md` substrate). The BP exposes a UFunction matching the delegate signature `(Succeeded: Bool, RequestId: Str, MeResponse: MeResponseV1, ErrorResponse: ErrorResponse)`; on fire, the BP forwards the payload to a Lua-readable bridge (mechanism chosen during Stage 5 — write to a property the Lua side polls/reads, or a `RegisterHook` on a sentinel UFunction the BP calls). The Lua side does `prop:Add(modActor, "OnMeResponse")` once at module init. **No polling loop.** Cold-start behaviour: wait for the natural login fire (the game itself triggers `MeRequestV1` during its login flow within ~RTT seconds of session start); the previously-considered "warm-cache one-shot via `GetCachedMeResponseV1`" pre-check is unavailable in this UE4SS build (see Stage-5 prerequisite outcome below).
- **Pros** — No polling at any point. Establishes the **ModActor delegate-bridge pattern as foundational substrate** for the codebase — every future feature that needs to react to game state changes (per-redirect events on `PMRockCharacter:LastRedirectKnockBack`, end-of-match hooks, achievement-condition triggers, async profile fetches for remote players, `GetDisplayNameV1Completed`) reuses the same BP wrapper + binding plumbing instead of reinventing a poll loop. Compounds the spike + Stage-5 substrate cost across the full wedge. The BP wrapper requirement turns out to be **table stakes for any UFunction-based identity path in this UE4SS build** (see R-A / R-C reframing below) — choosing R-B doesn't pay an extra-substrate tax over R-A / R-C, it just uses the same substrate reactively instead of synchronously.
- **Cons** — Requires a Blueprint actor delivered via the existing `mod-actor-pattern.md` substrate (BP class + cook step + `BPModLoaderMod` spawn) and a Lua-BP bridge mechanism (specific shape chosen during Stage 5). Cold-start window is "wait for natural login fire" (~RTT seconds, not user-perceptible at session start) rather than the originally-designed "warm-cache instant read"; the Stage-5 prerequisite below documents why the warm-cache fast-path is no longer available via UFunction call. Pure-Lua delegate binding does not exist; this is not a UE4SS limitation we can route around without BP, per `docs/learnings/ue4ss-lua-multicast-delegate-binding.md`.
- **Cost to build** — Medium-high (BP wrapper + cook step + Lua-BP bridge + delegate subscription; spike is complete; substrate amortizes across every future event-driven feature).
- **Cost to change later** — Low.

#### R-C — Hybrid (sync polling, delegate fallback after N retries)

- **What it is** — R-A by default. If `WasCached == false` after ~10 seconds (configurable), additionally subscribe to the delegate. Whichever path delivers the response first wins; the other deduplicates.
- **Pros** — Conceptually: fast happy path (warm cache) + robust slow path (cold start). Handles both scenarios without indefinite polling and without requiring delegate-binding for the common case.
- **Cons** — Most code. Two paths to test. Dedup logic required (don't emit identity event twice). **Same Pass-4 build-blocker as R-A on its sync half:** the warm-cache UFunction call doesn't work in this build, so the "warm cache" arm of the hybrid silently degrades to "wait the configured N seconds, then subscribe anyway". With the warm path effectively dead, the hybrid collapses into "delayed R-B" — strictly worse than R-B itself, while still paying R-B's full BP-wrapper cost.
- **Cost to build** — Medium-high (R-B's substrate cost + sync-polling glue that doesn't actually win the race in this build + dedup logic for a happy path that never fires).
- **Cost to change later** — Low.

### Trust posture — Sub-options (orthogonal to P/R)

- **T-α — Trust-on-claim.** Sidecar reports what the local game reports. No relay-side verification. Same posture as the archived position. **Pros:** zero infra cost. **Cons:** a modded client can spoof another player's Prometheus ID. The cost-to-attack is medium (requires Lua mod + relay protocol knowledge); the value-of-attack is low at MVP scope (no currency, no moderation, no exclusive grants).
- **T-β — Verified via Odyssey backend handshake.** Sidecar exchanges a Steam ticket / Odyssey OAuth token to validate the claimed Prometheus ID. **Pros:** spoof-resistant. **Cons:** requires reverse-engineering Odyssey's auth handshake (NDA territory per the Strikr-GG case in `os-prometheus-api-ecosystem.md`); creates a hard dependency on Odyssey's backend cooperation, **violating product anti-goal #3 ("survives the next Odyssey patch with zero work").** Not feasible at MVP.

## Decision

**Bind OSPlus profile rows to the Prometheus ID (Option P-B), resolved via the event-driven path (Option R-B), under trust-on-claim posture (Sub-option T-α).** SteamID retained as a secondary indexed column for cross-reference and as a fallback-display affordance.

Rationale, in order:
1. **P-B over P-A** — the platform-agnostic requirement is non-negotiable (maintainer-stated). P-A's "do this work later" cost is the same work P-B does now, plus a migration. Tracker-interop bonus is decisive among the close calls.
2. **P-B over P-C** — premature flexibility tax. P-C optimizes for a multi-platform world that isn't observed yet; if it materializes, the cost of adding a secondary identifier to a P-B schema is small.
3. **R-B over R-A** — Pre-Pass-4 framing was "R-A is easier now, R-B compounds long-term." Post-spike, that comparison sharpens: R-A's `GetCachedMeResponseV1` poll target doesn't work from Lua in this UE4SS build (any version of R-A also pays the BP-wrapper cost), and R-A's failure mode (indefinite silent retry on a warm-cache check that may never even succeed at the calling-convention layer) is worse than R-B's (subscribe once, wait for the natural login fire that the game itself triggers). **OSPlus's wedge surfaces are dominated by reactive game state** (per-redirect events, end-of-match hooks, achievement-condition triggers, remote-player profile arrivals); landing the delegate-bridge pattern at substrate time means each of those features reaches for the established BP-bridge primitive instead of re-inventing either a poll loop or its own BP wrapper.
4. **R-B over R-C** — R-C was "two paths so neither has to be solid." Post-spike, R-C's "fast warm-cache happy path" doesn't fire in this UE4SS build (same UFunction-marshaling block), so R-C collapses into "delayed R-B with extra dedup glue" — strictly worse than R-B itself for the same substrate cost. Pay the BP-bridge substrate once; reuse forever.
5. **T-α over T-β** — T-β's dependency on Odyssey's backend violates anti-goal #3. The threat model at MVP doesn't justify that cost. Reopen for T-β if a future ADR introduces currency / trade / moderation.

**Conditional:** This ADR is acceptable for MVP and remains acceptable until any of the *Revisit triggers* below fires.

**Acceptance prerequisite — STATUS: MET (spike complete 2026-04-24).**

The Pass-4 delegate-binding spike (probe source: `docs/features/pass2-probes/pass2_probes.lua`, F8 keybind, four iterative revisions through native-crash forensics) ran end-to-end and characterized R-B's substrate. The spike was framed as "does R-B's substrate exist? — if not, R-A vs R-C becomes the actual choice." Result: **R-B's substrate exists, with one design caveat absorbed into R-B's revised description above.**

*Discovery output:*

- **Subscription substrate (D1) — viable, requires ModActor BP wrapper.** UE4SS's `MulticastDelegateProperty:Add` takes `(UObject targetObject, FName | string functionName)` per the [official UE4SS docs](https://docs.ue4ss.com/dev/lua-api/classes/multicastdelegateproperty.html), confirmed by [PR #1073 (Lua: Delegate support, merged Nov 2025)](https://github.com/UE4SS-RE/RE-UE4SS/pull/1073). It does **not** accept a Lua function as the binding target — passing one is a native C++ access violation (Rev-3 crash forensics: `pcall` does not catch it; `OSPlusProbes.log` last-line was the killer call, no Lua-level error). The binding target must be a UObject with a real UFunction; in OSPlus that means a Blueprint actor delivered via the existing `mod-actor-pattern.md` substrate. Spike's introspection of the prop userdata (Rev-4, F8) read-probed all method-name candidates and confirmed only the documented six (`Add`, `Remove`, `Clear`, `Broadcast`, `GetFName`, `GetClass`) resolve to real `function` types — every other guessed name returns a placeholder `userdata` (UE4SS's `__index` does not return `nil` for unknown keys; this is the *specific* trap that bit Rev 3). Full pattern + false-friend trap captured in `docs/learnings/ue4ss-lua-multicast-delegate-binding.md`.
- **Cache pre-check substrate (D2) — not available via UFunction in this UE4SS build.** Spike swept three `PMPlayerModel` `(Bool out, X out)` UFunctions across all documented placeholder shapes: `GetCachedLinkCodeV1` (Bool + Str), `GetCachedPlayerPublicProfile` (Bool + Struct), `GetCachedMeResponseV1` (Bool + Struct). Every shape failed at the marshaling layer (`(arg, nil)` → "expected 2 parameters, received 1" since trailing nil is dropped; `(arg, {})` → `"Tried storing reference to a Lua table for an 'Out' parameter when calling a UFunction but no table was on the stack"`; `()` → "received 0"). The failure pattern matches the `(Bool out, X out)` shape independent of the X-type, so the warm-cache fast-path designed into pre-spike R-B is **not implementable via direct Lua UFunction call** in this build. Captured in `docs/learnings/ue4ss-outparam-marshaling-failure.md`. Cold-start for R-B is now "wait for natural login fire" (the game itself dispatches `MeRequestV1` during its login pipeline within ~RTT seconds of session start — empirically not user-perceptible at the Stage-5 use-site of "have identity ready by the time the first IPC handshake needs it").

R-B's substrate exists; R-A and R-C inherit the same UFunction-marshaling block, which is what tipped the rationale post-spike (see Decision points 3 and 4). The two halves of the original prereq are answered honestly: D1 viable with documented cost, D2 unavailable as designed (replaced by "wait for natural fire" in R-B's revised description).

**Stage-5 prerequisite (blocks build, not sign-off) — STATUS: ANSWERED (negative; pivot documented).**

The original prereq asked which placeholder shape works for `GetCachedMeResponseV1`. Spike answer: **none**, in this UE4SS build. Stage-5 build path therefore pivots: the warm-cache pre-check is removed from scope; R-B's cold-start path is "subscribe → wait for natural login fire" rather than "read cache → fall back to delegate." If a future feature needs synchronous cache reads, options are (a) direct property-read on `PMPlayerModel`'s underlying cache fields (untested — needs a property-dump probe; deferred), (b) a BP-side `GetCachedMeResponseV1` call routed back into Lua via the same ModActor bridge as D1 (BPs can call UFunctions natively without UE4SS's marshaling layer), or (c) a UE4SS upgrade if the marshaling-failure pattern is fixed in a later version. None gate this ADR.

## Consequences

**What this commits us to:**

- A new ModActor BP (proposed slug `BP_OSPlusDelegateBridge`) delivered via the existing `mod-actor-pattern.md` substrate, with a UFunction matching `MeRequestV1Completed__DelegateSignature` (`(Succeeded: Bool, RequestId: Str, MeResponse: MeResponseV1, ErrorResponse: ErrorResponse)`) that forwards the payload to a Lua-readable bridge. Bridge mechanism is a Stage-5 design choice (write to a watched property the Lua side reads via `RegisterHook` on the BP's notification UFunction is one candidate; specifics belong in the Stage-5 design pass, not this ADR).
- `mod/OSPlus/scripts/identity.lua` extends to: (1) acquire the spawned ModActor instance at module init, (2) call `prop:Add(modActor, "OnMeResponse")` once on `PMPlayerModel.GetMeRequestV1Completed`, (3) on bridge fire, capture `PlayerId` from `MeResponse`, (4) emit it alongside the existing SteamID + display-name fields. No polling loop and no warm-cache pre-check — the cold-start path waits for the game's natural login fire (~RTT seconds, not user-perceptible at the Stage-5 use-site).
- The ModActor delegate-bridge pattern becomes a **reusable codebase primitive.** Future features that need to react to game state (per-event redirect capture, end-of-match hooks for `in-game-profile-mvp`'s capture surface, achievement-condition triggers, remote-player profile arrivals via `GetDisplayNameV1Completed`) reuse the same BP-bridge plumbing — adding a new delegate subscription is "one new BP UFunction matching the new signature + one new `prop:Add` call from Lua", not a fresh substrate build. Captured in `docs/learnings/ue4ss-lua-multicast-delegate-binding.md`.
- Sidecar wire format (and relay handshake) carries `prometheusId` as the canonical player key. Existing `steamId`-keyed wire formats are deprecated; one migration step happens during Stage-5 build of `in-game-profile-mvp`. The migration plan lands in `0002-profile-storage`.
- Profile row schema starts with: `prometheusId TEXT PRIMARY KEY`, `steamId TEXT NULL` (indexed), `displayName TEXT`, `currentPlatform TEXT` (Steam / etc.), `logoId / nameplateId / emoticonId / titleId TEXT` (cosmetic loadout — surfaced in the same `MeResponseV1` call, useful for the eventual unlockable feature without an extra round-trip), `createdAt`, `updatedAt`. Exact column types and storage location land in `0002-profile-storage`.
- Cross-tracker interop becomes possible (any future feature that wants to enrich a profile with `clarioncorp.net` / `strikr.gg` data has the joinable key without a new resolution layer).
- A profile row can exist for a player who has never connected via Steam — `steamId` may be `NULL`.

**What this rules out — until a future ADR supersedes this:**

- Anti-impersonation guarantees. Any feature whose security model depends on Prometheus ID being authentic is out of scope until a follow-up ADR introduces T-β.
- Treating SteamID as the primary key in any subsystem. Cross-reference only.
- "Live re-resolve mid-match" patterns. Identity resolves once per OSPlus session at startup. Mid-session changes (player logs out and back in within the same OSPlus run) are not handled — would require an explicit re-resolve hook.
- Composite-key flexibility. Adding a second primary identifier (e.g., Epic ID) later requires a small schema change but doesn't require ADR supersession (the ADR commits to *Prometheus ID as primary*; secondary indexed columns are policy under it).

**Revisit triggers:**

- First feature whose threat model requires authenticated identity (currency / trading / moderation actions / earned exclusivity gated by identity authenticity).
- Odyssey ships an official auth or identity API (cheap path to T-β opens up).
- A confirmed in-the-wild spoofing case affecting a real OSPlus user.
- The first non-Steam OS launch is observed in OSPlus telemetry — not a trigger for revisiting *this* decision (it confirms the platform-agnostic requirement was load-bearing); worth recording as ADR-validation evidence.
- A UE4SS update or game patch breaks the ModActor delegate-bridge R-B depends on after acceptance — chosen path no longer implementable. ADR re-opens with current state as new context. (Pre-acceptance spike findings are folded into the *Acceptance prerequisite* status above, not into this trigger.)
- A UE4SS update fixes the `(Bool out, X out)` UFunction-marshaling failure characterized in Pass-4 — opens a cheaper path for any *future* synchronous cache-read need (does not invalidate the present R-B choice for identity, since R-B's reactive substrate is still right on its merits, but reopens the "warm-cache pre-check" sub-decision if a follow-up feature wants it).

## Related

- **Forced by feature:** `docs/features/in-game-profile-mvp.md` (Feasibility Pass 3 verdict — both identity surface and capture surface unblocked).
- **Background research:**
  - `docs/learnings/os-prometheus-api-ecosystem.md` — the "Prometheus" backend API ecosystem, tracker keying conventions, the SteamID/Prometheus-ID/display-name three-namespace distinction.
  - `docs/learnings/os-runtime-data-model.md` — runtime data model: `PlayerPublicProfile` shape, `MeResponseV1` inheritance, `PMPlayerModel` UFunction signatures, the delegate property's offset/type. (Pass-3 substantive findings; the calling-convention claim was falsified in Pass-4 — see the two learnings below.)
  - `docs/learnings/ue4ss-lua-multicast-delegate-binding.md` — Pass-4 spike output: `prop:Add(uobject, fname)` API + Lua-callback false-friend trap + introspection method.
  - `docs/learnings/ue4ss-outparam-marshaling-failure.md` — Pass-4 spike output: `(Bool out, X out)` UFunctions are unreachable from Lua in this UE4SS build; workaround paths.
- **KB references:** `KNOWLEDGEBASE.md` → *Player Identity Reference* (three-identifier table), *Backend Ecosystem*, *Per-match runtime data*.
- **Code locations** (post-acceptance — file-level changes during Stage 5 build):
  - `mod/OSPlus/scripts/identity.lua` — extends to surface `prometheusId`. Add `-- See docs/decisions/0001-identity-model.md` at the resolution function.
  - `server/profile/index.js` (untracked exploration) — schema + REST API; adopts the new schema.
  - Sidecar handshake module (path TBD by Stage 5) — wire format change.
- **Adjacent ADRs:**
  - `0002-profile-storage` (also forced by `in-game-profile-mvp`) — answers *where* profile rows physically live and *how* the schema migration lands. This ADR defines the row's identity; that ADR defines its home.
- **Supersedes:** `docs/decisions/_archive/vision-v1-superseded.md` → Lock 1. The archive is intentionally not numbered as an ADR; this ADR replaces Lock 1's commitment in full. No further `Status` field to update on the archive (it's already marked as the whole-document supersession).

## Notes

- The Pass-3 finding that `MeResponseV1` extends `PlayerPublicProfile` (`sps` chain in the UObject dump) is what makes the resolution path cheap. Without that inheritance, getting both Prometheus ID and the cosmetic loadout would require multiple calls. Don't lose sight of this in implementation — call once, populate everything.
- **Maintainer-stated principle that informed R-B over R-A:** "We should always prefer event-driven over polling." This ADR records the principle's first concrete application but does not codify it as a project-wide rule — that would be `AGENTS.md` / a rules-file change, separate scope. If the principle holds across two or three more ADRs, it's worth elevating then.
- The pre-spike R-B implementation included a subscribe-time cache pre-check (`GetCachedMeResponseV1` once, then subscribe) as a defensive warm-start. The Pass-4 spike falsified that path's availability in this UE4SS build (see *Acceptance prerequisite — Discovery output → D2*); R-B's revised cold-start posture is "subscribe → wait for the natural login fire", which is empirically not user-perceptible at the Stage-5 use-site. Re-introducing a warm-cache pre-check is a future option (BP-routed UFunction call, direct property read, or UE4SS-upgrade path), tracked in *Revisit triggers*.
- The Pass-4 spike output is captured across two learnings:
  - `docs/learnings/ue4ss-lua-multicast-delegate-binding.md` — the corrected `prop:Add(uobject, fname)` API + the Lua-callback false-friend trap (Rev-3 native crash) + the metatable-hidden-by-`__index` introspection trap. This is the substrate primitive that future feature work (capture surface, achievements, EOG hooks, remote-profile arrivals) builds on.
  - `docs/learnings/ue4ss-outparam-marshaling-failure.md` — the `(Bool out, X out)` UFunction marshaling block in this UE4SS build, with the specific error patterns per placeholder shape so future agents don't re-RE the failure. Workarounds documented.
- If Stage 5 discovers `MeResponseV1.PlayerId` is empty for any local player who has bypassed the Odyssey EULA flow (e.g., first-launch before consent), this ADR may need a sub-decision on synthesizing a stable per-install random ID for "guest" rows. Not anticipated; flagged as a discovery scenario rather than a pre-decided branch.
- The composite-key option (P-C) is honestly tempting for a "we'll regret hardcoding the schema" gut feeling — but the rule is "two real options with honest pros and cons" and P-C's *honest* con is that it solves a problem no observed user has yet. Naming that explicitly so a future ADR doesn't dust it off as "the obvious flexible answer we should have picked."
