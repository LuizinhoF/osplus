# ue4ss-cold-start-hook-install-pattern

| Field | Value |
|---|---|
| Date | 2026-04-25 |
| Area | re |
| Tags | ue4ss, lua, register-hook, notifyonnewobject, findfirstof, cold-start, install-timing, probe-design, false-negative, deferred-install-gap |
| Status | confirmed (revised same-day after production deploy uncovered a follow-on failure mode; see *Pattern selection* and lesson #4) |

## Symptom

Pass 6 of the ADR 0001 spike registered `RegisterHook(Pre|Post)` on every UFunction across two relevant classes (44 on `PMPlayerModel`, 35 on `PMIdentitySubsystem` — 79 total) to discover which fire during natural identity flow. The probe (`pass2_probes.lua`, `NUM_SIX` keybind, `probeE9`) was structured as a one-shot install activated by a keypress — press `NUM_SIX` once at the main menu after login, mass-install the 79 hooks, then immediately wait for naturally-fired callbacks tagged `[E9.HOOK]`.

**Result of Pass 6 v1: 79/79 hooks installed cleanly with zero registration failures, but `0 fires` captured across the entire post-install observation window.** Even after a full game restart + relogin (which re-runs the entire identity-bootstrap path), the post-relog `NUM_SIX` summary still reported zero fires for every hook.

The "0 fires" result is an exact false-negative — the same 79 hooks running in Pass 6 v2 (install-at-module-load) caught 4 UFunctions firing during the same login flow, with structured per-fire payloads. The substrate works; the v1 install timing didn't.

## Root cause

**`MeRequestV1`-class identity events fire during the login window — between game-process start and "main menu interactive" — which is *before* any user keypress is possible.** Pass 6 v1's install path was:

```
Lua module loads
   → registers RegisterKeyBind(NUM_SIX, probeE9)
   → waits for keypress
   ↓
[engine reaches main menu, login flow runs, MeRequestV1 fires here]
   ↓
User reaches main menu, presses NUM_SIX
   → probeE9 mass-installs 79 RegisterHooks  ← TOO LATE
   → waits for next fire
   ↓
[no further identity flow until next login → no fires captured]
```

The window where the events the probe wants to catch actually fire is *between* "Lua module load" and "user interaction possible." A keypress-driven install can't reach that window by construction. Quitting + relogging didn't fix it because re-login re-runs the full game process — by the time the user is at the main menu of the *new* process to press `NUM_SIX` again, the new login flow has already completed and the hooks installed by the previous (now-dead) Lua process are gone.

This is a **probe-design bug, not a substrate bug**. The same classification applies to any UE4SS feature whose target events fire at engine startup, world load, login, or any other "before user interaction is possible" moment.

## Fix

**For any UFunction that may fire during cold start, install the hook at Lua module load time. Use `NotifyOnNewObject` (for instances that come into existence after Lua loads) plus `FindFirstOf` as a one-shot fallback (for instances that already exist when Lua loads — the race condition where Lua loads slightly later than the engine instantiates the target class).** This is the maintainer-recommended pattern per [UE4SS Issue #455](https://github.com/UE4SS-RE/RE-UE4SS/issues/455).

```lua
-- Pass 6 v2 install pattern — replaces Pass 6 v1's RegisterKeyBind-driven install.
-- The two-phase setup (FindFirstOf + NotifyOnNewObject) is necessary because we
-- don't know which side of the race wins on any given session: sometimes Lua
-- loads before the engine constructs the target class (NotifyOnNewObject path),
-- sometimes after (FindFirstOf path).

local INSTALLED_FOR = {}  -- per-class guard so we install at most once

local function tryInstallByLookup(className, hookPathPrefix)
    if INSTALLED_FOR[className] then return false end
    local instance
    pcall(function() instance = FindFirstOf(className) end)
    if not instance or not instance:IsValid() then
        -- instance doesn't exist yet; NotifyOnNewObject will fire when it does
        return false
    end
    INSTALLED_FOR[className] = true
    installHooksOnInstance(instance, hookPathPrefix)
    return true
end

-- 1) FindFirstOf one-shot at module load — covers the case where the engine
--    already instantiated the target before Lua got control.
tryInstallByLookup("PMPlayerModel",       "/Script/Prometheus.PMPlayerModel")
tryInstallByLookup("PMIdentitySubsystem", "/Script/Prometheus.PMIdentitySubsystem")

-- 2) NotifyOnNewObject — covers the case where Lua loaded before the engine
--    instantiated the target. The callback runs on the game thread (object
--    construction is game-thread-only); ExecuteInGameThread is defensive but
--    technically redundant.
NotifyOnNewObject("/Script/Prometheus.PMPlayerModel", function(instance)
    if INSTALLED_FOR["PMPlayerModel"] then return end
    ExecuteInGameThread(function()
        if INSTALLED_FOR["PMPlayerModel"] then return end
        INSTALLED_FOR["PMPlayerModel"] = true
        installHooksOnInstance(instance, "/Script/Prometheus.PMPlayerModel")
    end)
end)
NotifyOnNewObject("/Script/Prometheus.PMIdentitySubsystem", function(instance)
    -- ... same shape ...
end)
```

Three notes on this pattern:

1. **`NotifyOnNewObject` callback re-fires.** The callback runs once *per construction event* for the matching class — not just the first instance. The `INSTALLED_FOR` guard makes the install one-shot per class. Without it, a class re-instantiated mid-session (rare for `PMIdentitySubsystem`, possible for `PMPlayerModel` on map transitions) would re-install hooks and double-count fires.
2. **`FindFirstOf` is *not* a substitute for `NotifyOnNewObject`.** They handle opposite halves of the load-order race. Use both. The Pass 6 v2 logs show `FindFirstOf` won the race for `PMIdentitySubsystem` (instance already existed at module load) but `NotifyOnNewObject` won for `PMPlayerModel` (instance constructed after Lua loaded).
3. **Do NOT use `ExecuteInGameThread` inside the `NotifyOnNewObject` callback for time-sensitive cold-start hooks.** Object-construction notifications fire on the game thread already; the defer adds one frame (~16–30ms) of latency between *target instance constructed* and *hook actually registered*. For cold-start events that the engine fires *immediately after* construction (engine-internal probes like `GetIdentityState`, `OnPostInitialized`, etc.), 30ms is enough to lose the race entirely — see "Failure mode 2 (deferred-install gap)" below. **Call `RegisterHook` synchronously inside the `NotifyOnNewObject` callback unless you have a specific reason to defer.**

The keypress-driven install pattern remains valid for events that only fire after user interaction (e.g., chat sends, ping fires, end-of-match transitions). For cold-start events, use module-load install.

## Pattern selection: known UFunction path vs. discovery probe

**Two distinct cold-start install scenarios. They use different patterns. Conflating them is what created Failure mode 2 below.**

### Scenario A — known UFunction path (production code)

You already know which UFunction you want to hook (e.g., `/Script/Prometheus.PMIdentitySubsystem:GetIdentityState`). **Use direct `RegisterHook` at module load.** The UFunction lives in the class table, which is populated when the package (`/Script/Prometheus`) loads during engine startup — *before* any Lua mod loads. No instance is required for `RegisterHook` to register against the function path. This is the cheapest, fastest, lowest-latency path.

```lua
-- Production pattern for known UFunction paths. Mirrors OSPlus's existing
-- /Script/Engine.GameState:OnRep_MatchState hook in main.lua.
local ok, preId, postId = pcall(RegisterHook,
    "/Script/Prometheus.PMIdentitySubsystem:GetIdentityState",
    function(self) onMyHookFire(self) end)
if not ok then
    log.log("[!] RegisterHook failed: " .. tostring(preId))
end
```

`identity.lua` lives at this scenario. `main.lua`'s `OnRep_MatchState` hook lives at this scenario. **No `FindFirstOf`, no `NotifyOnNewObject`, no `ExecuteInGameThread`.**

### Scenario B — discovery probe (you don't know the UFunction yet)

You want to enumerate UFunctions on a class via `cls:ForEachFunction(...)` to mass-instrument them — e.g., a Pass-6-style "which of the 79 UFunctions on these two classes fires during identity flow?" probe. To enumerate UFunctions you need a class object, and the cheapest path to the class is via an instance: `instance:GetClass()`. **For this scenario, use the two-phase `FindFirstOf` + `NotifyOnNewObject` pattern documented above.** The deferred-install latency is acceptable because (a) you're enumerating, not single-targeting a fast-firing UFunction, and (b) discovery probes run for the entire session — even if the first fire is missed, subsequent fires still produce data.

`docs/features/pass2-probes/pass2_probes.lua`'s `probeE9` lives at this scenario.

### Choosing between them

| If you... | Use Scenario | Why |
|---|---|---|
| Know the exact UFunction path you want to hook | A (direct module-load `RegisterHook`) | Simpler, no race conditions, no install-latency gap |
| Need to enumerate UFunctions on a class to mass-hook | B (FindFirstOf + NotifyOnNewObject) | Enumeration requires the class, which requires an instance |
| Want to hook a UFunction by name on whichever instance comes into existence | A (the hook is on the function path, not the instance) | `RegisterHook` callback receives `self` as the first param, you can filter inside |

**Failure mode: starting in Scenario B for a Scenario-A use case.** The first revision of `identity.lua` did this — it used `FindFirstOf` + `NotifyOnNewObject` + `ExecuteInGameThread` because the *Pass-6 probe* used that pattern, and the production code copy-pasted the install machinery without questioning whether enumeration was actually needed. Result: the deferred install lost the race against the engine's first `GetIdentityState` call. Fixed by collapsing to direct module-load `RegisterHook` (Scenario A). **Always ask "do I actually need enumeration?" before reaching for the two-phase pattern.**

## Failure mode 2 — the deferred-install gap (post-deploy follow-on, same-day)

After Pass 6 v2 fixed the v1 false-negative, the v2 install pattern was lifted into production `mod/OSPlus/scripts/identity.lua` for the R-B identity resolver. Cold-start deploy log:

```
06:04:34.36  identity.lua module-load: FindFirstOf returns nil
             → registers NotifyOnNewObject(PMIdentitySubsystem) and waits
06:05:30.95  PMIdentitySubsystem instance constructed
             → NotifyOnNewObject callback fires SYNCHRONOUSLY on game thread
             → ExecuteInGameThread queues the install for next tick
06:05:30.96  RegisterHook actually runs (~14ms later)
             ↑↑↑ The engine's first GetIdentityState call almost certainly
                 fired in this window — no [IDENTITY] resolution log line.
```

**Root cause: `ExecuteInGameThread` defer added a one-frame latency window between subsystem construction and hook registration. The engine's identity-bootstrap code calls `GetIdentityState` immediately after construction (it's a synchronous internal probe — "is the subsystem authenticated yet?"), which fires in that gap.**

Pass 6 v2's logs masked this because the discovery probe's `FindFirstOf` happened to win the race for `PMIdentitySubsystem` in the probe session (instance already existed at probe load, presumably because OSPlusProbes was loaded later in the mod chain or after a different boot sequence). The `NotifyOnNewObject` + `ExecuteInGameThread` codepath was registered but never actually exercised for that class — its latency cost was invisible because it never fired.

**Fix: For Scenario A use cases (known UFunction path), don't use `NotifyOnNewObject` at all — call `RegisterHook` directly at module load.** For Scenario B use cases (discovery probes) where the deferred install is structurally necessary, accept the latency or call `RegisterHook` synchronously inside the `NotifyOnNewObject` callback (drop the `ExecuteInGameThread` wrapper). The "defensive thread-context" rationale for `ExecuteInGameThread` is unjustified — `NotifyOnNewObject` callbacks already fire on the game thread; the defer is pure latency cost with no safety benefit for `RegisterHook` calls.

## Lesson

**Four transferable insights, in priority order:**

1. **A "0 fires" probe result against a substrate that registered cleanly is a false-negative until you've validated the install timing.** Specifically: if the events you want to catch fire during cold-start (engine init, world load, login, server connect, any pre-interactive moment), a probe that installs hooks on a user keypress will *always* report 0 fires no matter how many UFunctions you instrument or how many times you restart. The probe didn't catch the events because it wasn't running yet, not because the events don't exist. Going forward: when designing a probe whose target events plausibly fire pre-interactive, install at module load and have the keypress trigger a *summary* (per-UFunction fire counts, ambient state snapshot), not the install itself. This generalizes beyond UE4SS to any "instrument-then-observe" probe pattern in any reactive system.

2. **`NotifyOnNewObject` + `FindFirstOf` one-shot is the canonical pattern for "install a hook on a target that may or may not exist yet at Lua-load time."** Both halves are required because Lua-load-vs-engine-init order is non-deterministic across sessions. The `INSTALLED_FOR` guard makes the install one-shot per class so the `NotifyOnNewObject` re-fire behavior doesn't cause double-installs. This pattern is documented as the maintainer-recommended approach in UE4SS Issue #455 (the same issue that resolved the multicast-delegate-binding pivot in Pass 5) — both halves of "how do I reactively listen to engine state from UE4SS Lua" come back to this issue.

3. **Probe design has its own failure modes that look like substrate failure modes.** Pass 6 v1's verdict — "79 hooks registered, zero fires" — was *exactly* what we'd expect to see if the substrate were broken at the dispatch layer (similar shape to Pass 5's silent-no-op finding for `prop:Add`). The instinct on first reading the v1 logs was "another silent-no-op class of bug, time to pivot R-B again." Recognizing this as install-timing rather than substrate-failure required noticing that the events we wanted to catch fire *before* the install ran — which is a different failure-mode category entirely. **A "substrate failure" diagnosis should always be cross-checked against "could my probe have been running at the right time to catch the event in the first place?"** before pivoting the architecture. The cost of asking is one minute of timing-trace analysis; the cost of skipping is the wrong pivot.

4. **Lift probe code into production at the call-shape level, not at the install-machinery level.** The discovery probe used `FindFirstOf` + `NotifyOnNewObject` + `ExecuteInGameThread` because it needed `cls:ForEachFunction(...)` enumeration, which requires an instance, which requires waiting. Production code knew the exact UFunction path and didn't need any of that machinery — but copy-pasted it anyway because "that's what worked in the spike." Result: 14ms of post-construction install latency lost the race against the engine's first `GetIdentityState` call, producing the install-only / no-resolution log shape (Failure mode 2 above). **When productionizing a spike, ask "which parts of the spike's machinery are actually load-bearing for the production use case?"** A spike that enumerates 79 UFunctions across two classes has different requirements than production code hooking one specific UFunction. The two-phase install pattern is correct for the former and pure overhead (with a latency cost that can break the call) for the latter. The fix here was to delete the install machinery and call `RegisterHook` directly at module load, mirroring `main.lua`'s existing `OnRep_MatchState` hook — a pattern that was already in the codebase, working, and *simpler* than what we wrote. The lesson generalizes: **before adding install machinery, scan the codebase for working precedents on the same primitive at the same lifecycle point.** OSPlus had the answer in `main.lua` the entire time.

A meta-point: **the install-timing bug was caught in Pass 6 v1 *because* we'd already invested in detailed per-fire structured logging.** The `[E9.HOOK]` callback dumps unwrapped param values + ambient `PlayerId` snapshots; the `[E9.boot]` and `[E9.A]` install-time markers explicitly log "installed N hooks" and "ambient PlayerId at install time." Reading the v1 logs against the install-time markers made the timing gap obvious. Without the install-time markers, "0 fires" looks identical whether the cause is substrate failure or install-timing failure. **Always log the install moment with enough context to triangulate "did the probe run before or after the events I wanted to catch?"** This generalizes to any instrumentation: log the entry point, log the install moment, log the observation window — only then is "0 events seen" diagnostic.

## Related

- **Probe source:** `docs/features/pass2-probes/pass2_probes.lua` — `probeE9` (Pass 6 v2) at the bottom of the file. The v1 → v2 diff is the canonical reference for the install-timing fix; v2's module-load install block is the copy-pasteable template for production use.
- **Probe log artifact:** `F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log` (not committed; reproducible via deploy + cold-start restart). Search for `[E9.boot]`, `[E9.A]`, `[E9.B]`, `[E9.HOOK]`.
- **Production code (Scenario A — known UFunction path):** `mod/OSPlus/scripts/identity.lua` — direct `RegisterHook` on `PMIdentitySubsystem:GetIdentityState` at module load. The first revision used the Pass-6 two-phase pattern verbatim and triggered Failure mode 2; the current revision deletes the install machinery and matches `main.lua`'s `OnRep_MatchState` hook style.
- **Production code (sibling Scenario A precedent):** `mod/OSPlus/scripts/main.lua` — `RegisterHook("/Script/Engine.GameState:OnRep_MatchState", ...)` at module load. This was the working precedent the codebase already had; identity.lua should have started here, not at the Pass-6 spike's install machinery.
- **ADR consuming this finding:** `docs/decisions/0001-identity-model.md` — R-B substrate's Stage-5 implementation depends on the install-at-module-load pattern. The ADR's *Acceptance prerequisite* section's Pass-6 v2 entry + the *Notes* section's "Three-pass spike pattern" lesson both reference this learning.
- **Sibling learning:** `docs/learnings/ue4ss-multicast-delegate-add-silent-noop.md` — the *other* shoe of UE4SS Issue #455. That learning answers "why we can't subscribe to the multicast delegate"; this one answers "how we install the `RegisterHook` substitute correctly."
- **Upstream sources:**
  - [UE4SS Issue #455 — Lua delegate alternatives via `NotifyOnNewObject` + `RegisterHook`](https://github.com/UE4SS-RE/RE-UE4SS/issues/455) — maintainer-recommended pattern. Documents both the "what to hook" question (originating engine UFunction, not the multicast delegate) and the "when to install" question (at module load via `NotifyOnNewObject`, not on demand).
  - UE4SS Lua API reference for `NotifyOnNewObject` and `FindFirstOf` — both are documented as standard globals; their interaction (race condition between Lua-load and engine-init order) is not explicitly called out in the docs. This learning fills that gap for OSPlus's institutional knowledge.
