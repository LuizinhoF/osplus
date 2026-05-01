# `ExecuteInGameThread(UnregisterHook(...))` corrupts UE4SS callback state, crashes ~90 min later

| Field | Value |
|---|---|
| Date | 2026-04-30 |
| Area | mod |
| Tags | ue4ss-3.0.1, registerhook, unregisterhook, executeingamethread, crash, callback-vector, long-uptime, deterministic, hook-lifetime |
| Status | confirmed (v46 ran 2+ hours on the user's machine without the prior crash signature, crossing the deterministic 88–93 min crash window twice over; v47 is the same fix with the temporary diagnostic instrumentation removed) |

## Symptom

Game crashed deterministically after **~88–93 minutes** of uptime, on the user's machine, every session, after the post-account-creation Lua build (`identity.lua` with `RegisterHook` on `PMIdentitySubsystem:GetIdentityState`) shipped. Two crashes captured at the **same RVA in UE4SS.dll** (`+0x915AC1`, WRITE access violation at `0x0`). The chat-only build — same UE4SS.dll, same machine, same UE4SS hooks except for the new identity hook — ran for multi-hour sessions without a single crash, on this machine and others.

Critically: **the Lua VM was completely healthy until the moment of the crash.** v45 instrumentation captured this directly:

- `ticksPerSec` held at 30 across the entire 93-minute session — no starvation, no slowdown.
- `profile.tick` ran 872 full passes during the first 29 seconds (cold-start identity resolution) and then short-circuited 100% of the time for the next 92 minutes (`full=872` constant, `short` growing linearly).
- The `[IDENTITY] [DIAG]` line showed `hookFires=2 postUnregFires=0 unregistered=true pidResolved=true` for **every minute of every minute** of the session — the hook fired exactly twice during cold-start, the unregister returned cleanly, and the engine never called `GetIdentityState` again.
- `last_tick.txt` beacon mtime was 16 seconds before the crash — Lua was still ticking at the moment UE4SS detonated.

So the cause was not Lua-side allocation churn (the prior `profile-tick-userdata-allocation-leak.md` lesson), and it was not a "leaky hook continues firing" issue. The Lua side was inert; UE4SS corrupted itself.

## Root cause

`identity.lua` introduced a new pattern not present in the chat-only build: after the first successful PID resolution from inside the `RegisterHook` callback for `PMIdentitySubsystem:GetIdentityState`, it called `ExecuteInGameThread(function() UnregisterHook(...) end)` to defer the unregister to the next tick. That single call is the bug.

**[UE4SS Issue #1180](https://github.com/UE4SS-RE/RE-UE4SS/issues/1180)** documents the underlying mechanism. UE4SS processes deferred actions every engine tick by iterating its `m_engine_tick_actions` `std::vector` via `std::erase_if`. If a callback inside that iteration causes the vector to reallocate (`emplace_back` from inside, or any mutation that grows the vector past its capacity), `std::erase_if`'s in-progress `memcpy` works with stale pointers — observed by the issue reporter as "the `memcpy` byte count was something like 26 MB for a vector that only had 2 elements." The result is corrupted callback state in UE4SS's own data structures. The corruption surfaces *later*, when something traverses the broken state and dereferences a NULL — often minutes or hours afterwards, depending on cadence.

Our specific path:

1. `RegisterHook` callback fires (inside UE4SS's hook dispatcher, on the game thread).
2. Inside the callback, we call `ExecuteInGameThread(function() UnregisterHook(...) end)` — this **pushes** to `m_engine_tick_actions`.
3. On the next engine tick, `process_simple_actions` / `process_delayed_actions` calls `std::erase_if` on `m_engine_tick_actions`. The action callback runs `UnregisterHook`, which mutates UE4SS's internal hook-callback table. UE4SS's `FCallbackGarbageCollector` runs ~1.7 seconds later and "Freed invalid callbacks!" Two seconds after our call, UE4SS logs `Unregistering native pre-hook (3)` and `Unregistering native post-hook (4)`.

The 2-second gap between our `pcall(UnregisterHook)` returning ok and the actual native pre/post hook teardown is the suspicious window. The teardown happens across multiple engine ticks while the game's UI continues calling `GetIdentityState` (which still has registered native hooks during that window). Whatever transient state UE4SS leaves in its callback tables during that window is what eventually detonates.

Same crash class (`WRITE @ NULL inside UE4SS.dll`), same long-uptime profile (issue reporter saw it after long-running sessions too), same vector reallocation root cause. The repro from the issue uses high-cadence `ExecuteInGameThread` to trigger fast — our pattern uses one rare call to trigger the corruption that surfaces ~90 minutes later.

The chat-only build's `OnRep_MatchState` `RegisterHook` uses the opposite lifetime policy: registered at module load, **never unregistered**. The hook body (chat.lua) handles all the early-out logic. That pattern has been stable for hundreds of player-hours on multiple machines.

## Fix

Remove the `deferredUnregisterHook()` call. Leave the `RegisterHook` registered for the session lifetime. The hook body already early-returns on `cachedPrometheusId`, so any rare post-resolution fire is a single `if cachedPrometheusId then return end` check — empirically observed at `hookFires=2` across 93 minutes (the engine empirically stops calling `GetIdentityState` once the local player is authenticated).

Diff (`mod/OSPlus/scripts/identity.lua`):

- Deleted the entire `deferredUnregisterHook` function (the `ExecuteInGameThread(function() UnregisterHook(...) end)` block).
- Deleted the `unregisterCalled` and `postUnregisterFires` instrumentation locals (no longer meaningful).
- Removed the `deferredUnregisterHook()` call from the end of `onIdentityHookFire`.
- Updated the `M.reset()` comment and the docstring above `cachedPrometheusId` to reflect the new "register once, never unregister" lifetime policy.
- Added a code-site comment in `onIdentityHookFire` pointing here.
- Bumped `config.lua` `M.VERSION` to `v46-no-unregister-hook`.

**Verification:** the v46 build ran for more than 2 hours on the user's machine without the prior crash signature, crossing the deterministic 88–93 minute crash window twice. v47 ships the same fix with the temporary v44/v45 diagnostic instrumentation (the `hookFireCount` counter + `[IDENTITY] [DIAG]` line in `identity.lua`, the `shortCircuitCount`/`fullRunCount` counters + `getDiagnostics` in `profile.lua`, and the `last_tick.txt` beacon + `[HEALTH]` log line in `main.lua`) removed for production cleanliness. The instrumentation pattern itself is recorded in the *Lesson* section below for fast re-deployment if a future long-uptime crash investigation needs the same telemetry.

## Lesson

**Don't use `ExecuteInGameThread` to mutate UE4SS-internal callback state.** This includes `UnregisterHook`, `RegisterHook`, `RegisterCustomEvent`/`UnregisterCustomEvent`, and `NotifyOnNewObject` listener install/teardown. These mutate the same data structures that UE4SS's per-tick action processor is iterating, and the mid-iteration mutation is the documented failure mode in [UE4SS Issue #1180](https://github.com/UE4SS-RE/RE-UE4SS/issues/1180).

Stronger transferable rule: **prefer "register once, never unregister" for hooks whose body is cheap.** The cost of leaving a hook registered for the session is one Lua early-return per fire; the cost of unregistering, against UE4SS 3.0.1, is a probabilistic latent crash 60–90 minutes later that's nearly impossible to attribute without instrumentation. The trade is asymmetric — keep the hook.

If you genuinely need to stop a hook from firing (the body has side effects you can't make idempotent, or the host UFunction is being called at high cadence and even an early-return is too much), the safer alternatives are:

1. **Conditional logic inside the hook body**, gated on a Lua-side flag (`if not active then return end`). Cost: nothing UE4SS-side.
2. **Direct `UnregisterHook` call from inside the hook callback**, no `ExecuteInGameThread` wrapper. UE4SS issues #455 and #827 confirm this is supported; the issue is specifically the deferred path through `m_engine_tick_actions`. Cost: small — but still mutates UE4SS hook-callback tables, which has its own historical bugs (#305, #467, #828); test with a long-run session before shipping.
3. **`RegisterHook` on a different UFunction** that fires less often. For identity, `GetIdentityState` was already a low-cadence UFunction (2 fires per session) — the unregister was unnecessary in the first place.

Anti-rule we previously believed: "deferring `UnregisterHook` via `ExecuteInGameThread` is the safer pattern when we don't need an immediate stop." The original `identity.lua` comment cited this as conventional wisdom. **It's wrong on UE4SS 3.0.1.** The deferred path is *less* safe than the direct call because it adds an `m_engine_tick_actions` push that participates in the documented vector-reallocation bug class. That comment has been replaced.

Methodology lesson worth keeping: the "instrument first, theorize later" pattern that produced this finding (v44/v45 instrumentation: per-tick beacon file, [HEALTH] log line every 60s, hook fire counter) is reusable. Specifically:

- A `last_tick.txt` beacon file rewritten every ~30 ticks pinpoints the crash time to within 1 second without needing a debugger attached.
- A pure-Lua `[HEALTH]` log line every 60s with `ticksPerSec` (computed from `tickCount/uptime`) catches loop starvation and slowdown that would otherwise be invisible until the symptom escalates.
- Pure-Lua int counters around any suspected hot path are essentially free and give "what really happened" data instead of "what we think happened" reasoning.

The first iteration of this investigation chased two falsified hypotheses (profile.tick allocation churn — partially correct but didn't fully explain the long-uptime crash; identity hook leak via continued post-unregister fires — completely false). The instrumentation is what made the third hypothesis actionable instead of speculative.

## Related

- Files: `mod/OSPlus/scripts/identity.lua` (the fix and the explanatory comments), `mod/OSPlus/scripts/config.lua` (`v46-no-unregister-hook`), `mod/OSPlus/scripts/main.lua` (the `[HEALTH]` log + `last_tick.txt` beacon instrumentation that captured the data).
- Prior learnings:
  - [`profile-tick-userdata-allocation-leak.md`](profile-tick-userdata-allocation-leak.md) — same crash family (UE4SS.dll access violation after long uptime), but different root cause (Lua-side per-tick allocation churn). The v43 fix from that learning was correct and necessary; this learning addresses a *separate* failure mode that was masked by the previous one until the v43 fix landed.
  - [`ue4ss-cold-start-hook-install-pattern.md`](ue4ss-cold-start-hook-install-pattern.md) — companion lesson on when to use `RegisterHook` vs `NotifyOnNewObject`. The "Pattern A: known UFunction path → direct RegisterHook at module load" advice still holds; this learning adds a corollary: **for Pattern A, don't unregister.**
  - [`ue4ss-multicast-delegate-add-silent-noop.md`](ue4ss-multicast-delegate-add-silent-noop.md) — same UE4SS-3.0.1-specific binary-quirk family; reinforces "test on the actual shipping UE4SS build, not on what the docs imply."
- Upstream: [UE4SS Issue #1180](https://github.com/UE4SS-RE/RE-UE4SS/issues/1180) — the full-stack analysis of the `m_engine_tick_actions` vector-reallocation bug, with repro mods and partial fix attempts. The mainline UE4SS branch has not shipped a verified fix as of the date of this learning; rather than wait for an upstream fix and pin to a build that isn't current 3.0.1, we sidestep by not using the buggy pattern.
- Tooling: `.crash-parse-2.py` (argument-driven minidump parser at repo root). Promotion to `tools/re/parse_minidump.py` was flagged in the prior learning and remains a TODO — use of this tool in two consecutive incidents now confirms it earns the promotion.
