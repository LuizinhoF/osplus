# ue4ss-outparam-marshaling-failure

| Field | Value |
|---|---|
| Date | 2026-04-25 |
| Area | re |
| Tags | ue4ss, lua, ufunction, out-params, marshaling, calling-convention, prometheus, identity |
| Status | confirmed |

## Symptom

Pass-4 spike for ADR 0001 attempted to call `PMPlayerModel.GetCachedMeResponseV1(WasCached: Bool out, OutMeResponse: MeResponseV1 out)` from UE4SS Lua to read the local player's cached profile. Every documented placeholder shape failed at the marshaling layer:

| Call shape | Error message |
|---|---|
| `model:GetCachedMeResponseV1(false, nil)` | `UFunction expected 2 parameters, received 1` (the trailing `nil` is dropped before reaching the marshaler) |
| `model:GetCachedMeResponseV1(false, {})` | `Tried storing reference to a Lua table for an 'Out' parameter when calling a UFunction but no table was on the stack` |
| `model:GetCachedMeResponseV1(false)` | `UFunction expected 2 parameters, received 1` |
| `model:GetCachedMeResponseV1()` | `UFunction expected 2 parameters, received 0` |

This is exactly the surface the *pre-spike* draft of `os-runtime-data-model.md` and `ADR 0001 — R-B` rested on: "do a one-shot `GetCachedMeResponseV1` read at subscribe time as the warm-cache fast-path." The substrate the design assumed exists at the engine level and is documented in the UE4SS object dump, but is not reachable through UE4SS's Lua calling glue in this build.

To rule out "maybe it's specific to this one UFunction" or "maybe it's specific to `Struct out`", the spike's Rev-4 sweep tested two more `(Bool out, X out)` UFunctions on the same class:

- `GetCachedLinkCodeV1` (Bool out, **Str** out) — same class of failure across all four shapes.
- `GetCachedPlayerPublicProfile` (Bool out, **Struct** out — `PlayerPublicProfile`, the parent struct of `MeResponseV1`) — same class of failure across all five shapes.

The failure pattern is uniform across the X-type and across the placeholder shape — not a one-off bug on one UFunction.

## Root cause

**UE4SS in this build (UE4SS v3.0.1, Omega Strikers branch) cannot marshal Lua call sites for UFunctions whose signature shape is `(Bool out, X out)`.** Two distinct sub-failures stack:

1. **Trailing `nil` arguments are dropped before the parameter count is checked.** Lua's calling convention drops trailing `nil`s in vararg / table-unpack contexts; UE4SS's caller sees `(false)` instead of `(false, nil)` and bails with "expected 2, received 1." This rules out the most commonly-quoted "pass nils for out-params" pattern.
2. **Passing a table as an out-param placeholder is rejected by UE4SS's stack-marshaler with "no table was on the stack."** This is the [error path documented in UE4SS issue #477 / referenced in PR threads around UFunction out-param handling](https://github.com/UE4SS-RE/RE-UE4SS/issues/) — the marshaler expects a UStruct-backed table on its own type stack, not a Lua-side `{}`. Constructing one from Lua isn't supported in v3.0.1.

The combined effect is that *no* documented Lua-side call shape works for the `(Bool out, X out)` signature class on `PMPlayerModel`. The UFunction itself is callable from Blueprint and from C++ — UE4SS is the failing layer, not UE.

For sibling cases that *do* work in this build (e.g. `PMIdentitySubsystem:GetSteamId()` returning a single output), the problem doesn't reproduce — single-output UFunctions go through a different (working) marshaling path. The failure is specific to the multi-output shape.

## Fix

There is no Lua-side fix in this UE4SS version. **Three workaround paths**, in increasing build cost:

1. **Direct property read** *(untested, plausible)*. Many UE games back `GetCached*` UFunctions with a UProperty field on the same UObject (e.g., `PMPlayerModel.CachedMeResponse : MeResponseV1` or similar). UE4SS exposes UProperty reads through `obj.PropertyName` without going through the UFunction marshaler. A property-dump probe on `PMPlayerModel` would identify whether such a field exists; if it does, this is a zero-build-cost workaround. **Deferred** — not needed for the current Stage-5 path (R-B's natural-login-fire cold start is sufficient), but worth a single-probe pass when the next feature wants synchronous cache reads.
2. **BP wrapper that calls the UFunction internally.** A Blueprint actor (delivered via `BPModLoaderMod`, per `mod-actor-pattern.md`) can call `GetCachedMeResponseV1` through Blueprint's native UFunction resolution — which doesn't go through UE4SS's Lua marshaler at all — and forward the `(WasCached, MeResponse)` payload back to Lua via a watched property or a notification UFunction Lua hooks. Same substrate ADR 0001's R-B already commits to for the delegate bridge; adds one more BP UFunction.
3. **UE4SS upgrade.** If a later UE4SS release fixes the `(Bool out, X out)` marshaling path, the original Lua-side call becomes viable again. Reopen this learning when an upgrade is attempted; verify with a fresh probe before assuming the fix applies.

For the current ADR 0001 / Stage-5 path, the chosen workaround is **none of the above** — R-B's revised cold-start posture removes the warm-cache pre-check entirely (wait for natural login fire). The workarounds above are documented for the next feature that needs synchronous cached reads (likely the remote-player profile cache for the wedge's "show another player's profile" surface).

## Lesson

**Three transferable insights:**

1. **For *any* UE4SS UFunction call from Lua, treat "the signature shows `(Bool out, X out)`" as a hard yellow flag.** This shape is broken across at least three UFunctions on `PMPlayerModel` in this build; assume it's broken everywhere until proven otherwise on a per-call basis. The class of UFunction this affects is wide — anything named `TryGet*`, `GetCached*`, `IsValid*` (when paired with an out struct) is suspect. When designing a feature around such a call, design the BP-wrapper escape hatch into the proposal *before* committing to a Lua-only path — don't discover it during the spike.
2. **A spike that probes a single UFunction is incomplete characterization of a UE4SS calling-convention question.** Pass-4 Rev-3 only probed `GetCachedMeResponseV1` and got "expected 2 parameters, received 0" — which initially looked like "maybe just need different args." Rev-4's three-UFunction × four-shape sweep took ~5 extra minutes and conclusively pinned the failure to the *signature shape*, not the call site. Always sweep two-or-more UFunctions of the same shape when characterizing a marshaling-layer behaviour; one is just an anecdote.
3. **The `os-runtime-data-model.md` calling-convention claim ("`(false, nil)` is the call shape") was a guess from the UFunction signature alone, not from a working call.** That guess survived from Pass-3 through to ADR 0001's first draft because it was *plausible* and had no in-game probe to falsify it. Lesson: a UE4SS calling-convention claim should not enter a learning doc until a working call exists. Mark such claims as "design-time guess, not validated" in the learning until the spike confirms — pre-spike R-B's confidence in the warm-cache pre-check would have been calibrated lower if this discipline had been applied earlier.

## Related

- **Spike that produced this finding:** `docs/features/pass2-probes/pass2_probes.lua` — Pass 4 Rev-4, F8 keybind, `d2CacheFetch()` function (the three-UFunction sweep).
- **Probe log artifact:** `F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log` (not committed; reproducible by running the probe in-game).
- **ADR consuming this finding:** `docs/decisions/0001-identity-model.md` — pivots R-B's cold-start path from "warm-cache pre-check via UFunction" to "wait for natural login fire" because of this finding; documents the workaround paths in *Revisit triggers* and *Stage-5 prerequisite outcome*.
- **Sibling Pass-4 finding:** `docs/learnings/ue4ss-lua-multicast-delegate-binding.md` — the delegate-subscription substrate (D1) was the other half of the spike. D1 is viable with ModActor cost; D2 (this learning) is not viable in Lua. Both shape Stage-5 path together.
- **Updates to:**
  - `docs/learnings/os-runtime-data-model.md` — pre-spike claim that `(false, nil)` is the working call shape is falsified; that doc was edited in the same branch to point here.
  - `KNOWLEDGEBASE.md` → *Per-match runtime data* / *Player Identity Reference* — same correction.
- **Reference substrate (workaround #2):** `.cursor/skills/ue4ss-modding/references/mod-actor-pattern.md` — the BP-wrapper-for-UFunctions pattern.
- **UE4SS version pin:** v3.0.1, the version shipped with the OSPlus dev environment as of 2026-04-25. Re-test after any UE4SS upgrade.
