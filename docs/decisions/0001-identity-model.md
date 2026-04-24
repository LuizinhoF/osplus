# ADR 0001 — Bind OSPlus profiles to the Odyssey (Prometheus) account ID

| Field | Value |
|---|---|
| Status | `proposed` |
| Date | 2026-04-24 |
| Forcing feature | `feat/in-game-profile-mvp` (Stage 3 / Feasibility complete; Stage 4 blocked on this ADR) |
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
- **Pros** — Simplest. Single call, single source of truth. Reuses `identity.lua`'s existing poll loop.
- **Cons** — If the local PMPlayerModel cache hasn't filled by the time the script starts polling, `WasCached == false` indefinitely. Resolution becomes a "poll until success" question with no upper bound. Risk: rare cold-start window where OSPlus loads before the game's network resolution completes.
- **Cost to build** — Small.
- **Cost to change later** — Low — internal to `identity.lua`.

#### R-B — Event-driven (multicast delegate)

- **What it is** — Subscribe to `/Script/Prometheus.MeRequestV1Completed__DelegateSignature` (or `GetDisplayNameV1Completed__DelegateSignature`) at script load. The callback receives a `MeResponse` struct; capture `PlayerId`. To handle the case where the request already completed before subscription, do a one-shot `GetCachedMeResponseV1` read at subscribe time — cache hit short-circuits to the same handler; cache miss waits for the delegate. No polling loop in either path.
- **Pros** — No polling at any point. The subscribe-time cache read is a single check, not a loop. Establishes the **delegate-binding pattern as foundational substrate** for the codebase — every future feature that needs to react to game state changes (per-redirect events on `PMRockCharacter:LastRedirectKnockBack`, end-of-match hooks, achievement-condition triggers, async profile fetches for remote players) reuses the same plumbing instead of reinventing a poll loop. Compounds the spike cost across the full wedge.
- **Cons** — UE4SS Lua delegate-binding patterns are not currently exercised in this codebase. Validating the binding mechanics adds an RE spike before code lands (1–2 hours: confirm the binding API, confirm callback signature, confirm whether unsubscribe is supported / required). The subscribe-time cache pre-check is essential — without it, the script silently never resolves identity if it loaded after the local `MeRequest` completed.
- **Cost to build** — Medium (delegate-binding spike + implementation; spike is one-time and amortizes across future event-driven features).
- **Cost to change later** — Low.

#### R-C — Hybrid (sync polling, delegate fallback after N retries)

- **What it is** — R-A by default. If `WasCached == false` after ~10 seconds (configurable), additionally subscribe to the delegate. Whichever path delivers the response first wins; the other deduplicates.
- **Pros** — Fast happy path (warm cache); robust slow path (cold start). Handles both scenarios without indefinite polling and without requiring delegate-binding for the common case.
- **Cons** — Most code. Two paths to test. Dedup logic required (don't emit identity event twice).
- **Cost to build** — Medium-high (R-A + R-B's validation spike + dedup glue).
- **Cost to change later** — Low.

### Trust posture — Sub-options (orthogonal to P/R)

- **T-α — Trust-on-claim.** Sidecar reports what the local game reports. No relay-side verification. Same posture as the archived position. **Pros:** zero infra cost. **Cons:** a modded client can spoof another player's Prometheus ID. The cost-to-attack is medium (requires Lua mod + relay protocol knowledge); the value-of-attack is low at MVP scope (no currency, no moderation, no exclusive grants).
- **T-β — Verified via Odyssey backend handshake.** Sidecar exchanges a Steam ticket / Odyssey OAuth token to validate the claimed Prometheus ID. **Pros:** spoof-resistant. **Cons:** requires reverse-engineering Odyssey's auth handshake (NDA territory per the Strikr-GG case in `os-prometheus-api-ecosystem.md`); creates a hard dependency on Odyssey's backend cooperation, **violating product anti-goal #3 ("survives the next Odyssey patch with zero work").** Not feasible at MVP.

## Decision

**Bind OSPlus profile rows to the Prometheus ID (Option P-B), resolved via the event-driven path (Option R-B), under trust-on-claim posture (Sub-option T-α).** SteamID retained as a secondary indexed column for cross-reference and as a fallback-display affordance.

Rationale, in order:
1. **P-B over P-A** — the platform-agnostic requirement is non-negotiable (maintainer-stated). P-A's "do this work later" cost is the same work P-B does now, plus a migration. Tracker-interop bonus is decisive among the close calls.
2. **P-B over P-C** — premature flexibility tax. P-C optimizes for a multi-platform world that isn't observed yet; if it materializes, the cost of adding a secondary identifier to a P-B schema is small.
3. **R-B over R-A** — `R-A`'s polling loop is the easy choice now and the wrong one over time. **OSPlus's wedge surfaces are dominated by reactive game state** (per-redirect events, end-of-match hooks, achievement-condition triggers, remote-player profile arrivals); landing the delegate-binding pattern at substrate time means each of those features reaches for an established primitive instead of re-inventing a poll loop. The polling failure mode (indefinite silent retry) is also worse than R-B's failure mode (silent stuck only if subscribe-time cache check is omitted, which the implementation explicitly handles).
4. **R-B over R-C** — R-C is "two paths so neither has to be solid." R-B with the subscribe-time cache pre-check is one path that is solid. The hybrid's polling fallback was solving a problem that R-B's pre-check solves more cleanly. Pay the delegate-binding spike once; reuse forever.
5. **T-α over T-β** — T-β's dependency on Odyssey's backend violates anti-goal #3. The threat model at MVP doesn't justify that cost. Reopen for T-β if a future ADR introduces currency / trade / moderation.

**Conditional:** This ADR is acceptable for MVP and remains acceptable until any of the *Revisit triggers* below fires.

**Pass-4 prerequisites (do not block sign-off, do block Stage 5 build):**

1. Confirm the UE4SS calling-convention for output-param placeholders on `GetCachedMeResponseV1` — `(false, nil)` is the expected shape, but `(false, {})` and a no-arg form are also seen in different UE4SS versions. One in-game probe call validates it.
2. **Delegate-binding spike (1–2 hours).** Confirm the UE4SS Lua API for binding to a multicast `*__DelegateSignature` (binding mechanism, callback signature shape with the `MeResponseV1` struct argument, whether unsubscribe is supported and how). Validates R-B's foundational mechanic before any feature relies on it. Output: a short snippet in `docs/learnings/` documenting the binding pattern so future features (capture surface, achievements) reuse it without re-RE.

The signatures themselves are settled (see `docs/learnings/os-runtime-data-model.md`); only the calling glue is open.

## Consequences

**What this commits us to:**

- `mod/OSPlus/scripts/identity.lua` extends to: (1) subscribe to `MeRequestV1Completed__DelegateSignature` at module init, (2) do a one-shot `GetCachedMeResponseV1` read at subscribe time as the warm-cache fast-path, (3) capture `PlayerId` from whichever path delivers first, (4) emit it alongside the existing SteamID + display-name fields. No polling loop introduced for identity.
- The delegate-binding pattern validated in Pass-4 becomes a **reusable codebase primitive.** Future features that need to react to game state (per-event redirect capture, end-of-match hooks for `in-game-profile-mvp`'s capture surface, achievement-condition triggers, remote-player profile arrivals) build on the same primitive — no parallel poll loops. Captured in a learning doc so future agents don't re-RE the binding mechanic.
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
- The Pass-4 delegate-binding spike fails or surfaces a UE4SS limitation that makes R-B uneconomical at this build version — would force a fallback to R-C or a different resolution path entirely. ADR re-opens with the spike findings as new context.

## Related

- **Forced by feature:** `docs/features/in-game-profile-mvp.md` (Feasibility Pass 3 verdict — both identity surface and capture surface unblocked).
- **Background research:**
  - `docs/learnings/os-prometheus-api-ecosystem.md` — the "Prometheus" backend API ecosystem, tracker keying conventions, the SteamID/Prometheus-ID/display-name three-namespace distinction.
  - `docs/learnings/os-runtime-data-model.md` — runtime data model: `PlayerPublicProfile` shape, `MeResponseV1` inheritance, `PMPlayerModel` UFunction signatures, calling convention.
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
- The R-B implementation includes a subscribe-time cache pre-check (`GetCachedMeResponseV1` once, then subscribe). This is **not** a hybrid with R-A — it's a single defensive read at module init, not a polling loop. The distinction matters: R-A's failure mode is "polls forever waiting for a cache fill that may never come"; R-B's is "subscribes, checks cache once, waits for delegate." Both R-A and R-B's failure modes resolve under the right conditions, but R-B doesn't burn CPU while waiting.
- The delegate-binding spike output should land in `docs/learnings/` (proposed slug: `ue4ss-lua-delegate-binding.md`) so future feature work — capture surface, achievements, EOG hooks — doesn't have to repeat the RE. This is the compounding investment R-B's rationale rests on.
- If Stage 5 discovers `MeResponseV1.PlayerId` is empty for any local player who has bypassed the Odyssey EULA flow (e.g., first-launch before consent), this ADR may need a sub-decision on synthesizing a stable per-install random ID for "guest" rows. Not anticipated; flagged as a discovery scenario rather than a pre-decided branch.
- The composite-key option (P-C) is honestly tempting for a "we'll regret hardcoding the schema" gut feeling — but the rule is "two real options with honest pros and cons" and P-C's *honest* con is that it solves a problem no observed user has yet. Naming that explicitly so a future ADR doesn't dust it off as "the obvious flexible answer we should have picked."
