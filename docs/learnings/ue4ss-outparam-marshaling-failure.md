# ue4ss-outparam-marshaling-failure

| Field | Value |
|---|---|
| Date | 2026-04-25 |
| Area | re |
| Tags | ue4ss, lua, ufunction, out-params, marshaling, calling-convention, prometheus, identity |
| Status | **partially superseded 2026-04-25** — call-shape conclusion refuted (the `({}, {})` shape works on UE4SS 3.0.1); `PMPlayerModel:GetCached*V1` reachability untested with the new shape (see banner) |
| UE4SS version | 3.0.1 (still our shipping version as of 2026-04-25) |

> **Supersession banner (added 2026-04-25 post-v35→v36 identity work):** This learning's headline conclusion — *"`(Bool out, X out)` UFunctions are not callable from Lua at all on UE4SS 3.0.1"* — is **refuted at the call-shape layer**. The Pass-4 matrix tested `(false, nil)`, `(false, {})`, `(false)`, and `()`, but never `({}, {})` — both out-params as empty table buckets, which is what UE4SS 3.0.1 actually wants for multi-out-param calls (see [UE4SS Issue #920](https://github.com/UE4SS-RE/RE-UE4SS/issues/920) for the convention, [Issue #971](https://github.com/UE4SS-RE/RE-UE4SS/issues/971) for the 3.0.1-specific multi-param-collapse behaviour). The `({}, {})` shape was confirmed working end-to-end against `PMIdentitySubsystem:GetAuthenticatedPlayerId(Valid: Bool out, OutPlayerId: Str out)` in OSPlus identity.lua v35 (the maintainer's personal Prometheus ID was successfully resolved). The new canonical convention + worked example + v33→v35 evolution is captured in **[`ue4ss-ufunction-out-param-marshaling-3-0-1.md`](ue4ss-ufunction-out-param-marshaling-3-0-1.md)** — that document is the load-bearing reference for any future out-param marshaling question on this build.
>
> **What remains valid in this document:**
> - The four failing call shapes (`(false, nil)`, `(false, {})`, `(false)`, `()`) and their exact UE4SS error messages — these still fail, and the wording-as-diagnostic discipline they exemplify is unchanged.
> - The Lua-trailing-`nil`-drop and "no table on the stack" mechanism explanations — these are also unchanged; the new doc adds the missing third row (`({}, {})`).
> - The general lesson about needing to characterize a marshaling-layer behaviour by sweeping multiple UFunctions of the same shape rather than guessing from one. **This was correctly applied here, but the sweep was over four shapes that are all wrong; what was missing was the fifth, correct shape.** The meta-meta-lesson — *"a sweep of four 'plausible' shapes that all fail does not prove the shape-class is unreachable; check the maintainer-recommended call shape from upstream issues filtered to your version before concluding"* — is captured in the new doc's Lesson section.
>
> **What is *not* re-validated by the v35 work:**
> - The specific `PMPlayerModel:GetCached*V1` UFunctions (`GetCachedMeResponseV1`, `GetCachedLinkCodeV1`, `GetCachedPlayerPublicProfile`) **were not re-tested with `({}, {})`** during the v33→v35 work. They may now be reachable (the `({}, {})` rule is shape-agnostic at the marshaling layer) or they may still fail for an orthogonal reason (e.g., `PMPlayerModel`-specific lifecycle issue). Treat them as "untested with new shape" and probe before relying. The corresponding KNOWLEDGEBASE entry has been updated to flag them as such.
> - The "Fix → workaround #1 (direct UProperty read)" path is still relevant if a `({}, {})` retest of those UFunctions also fails, but it is no longer the *primary* recommendation for the call-shape question itself — the empty-table call now is.

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

A subsequent Pass-5 attempt to use `PMPlayerModel:GetMeV1(WasSent: Bool out, OutRequestId: Guid out)` to **force-trigger** a `GetMeRequestV1Completed` delegate fire (i.e., a non-cache request UFunction with the same signature shape) reproduced the same failure:

- `GetMeV1(false, nil)` → `Tried storing reference to a Lua table for an 'Out' parameter when calling a UFunction but no table was on the stack`.

This is significant because `GetMeV1` is **not** a cache-read; it's an asynchronous request initiator. Same `(Bool out, X out)` shape, same failure mode — confirming the bug is signature-shape driven, not cache-semantics driven, and that **any** V1 request UFunction with this shape is unusable from Lua. Practical impact for ADR 0001: there is no Lua-callable way to force a `*RequestCompleted` delegate to fire in a controlled window for substrate validation. The R-B path is forced to depend on natural fires (login, mutations) for both validation AND production data flow.

The failure pattern is uniform across the X-type, the placeholder shape, AND the call semantic (cache read vs request initiator) — not a one-off bug on one UFunction.

## Root cause

**UE4SS in this build (UE4SS v3.0.1, Omega Strikers branch) cannot marshal Lua call sites for UFunctions whose signature shape is `(Bool out, X out)`** — regardless of whether `X` is `Struct` or `Str`, regardless of whether the UFunction is a cache read or an async request initiator. Two distinct sub-failures stack:

1. **Trailing `nil` arguments are dropped before the parameter count is checked.** Lua's calling convention drops trailing `nil`s in vararg / table-unpack contexts; UE4SS's caller sees `(false)` instead of `(false, nil)` and bails with "expected 2, received 1." This rules out the most commonly-quoted "pass nils for out-params" pattern.
2. **Passing a table as an out-param placeholder is rejected by UE4SS's stack-marshaler with "no table was on the stack."** This is the [error path documented in UE4SS issue #477 / referenced in PR threads around UFunction out-param handling](https://github.com/UE4SS-RE/RE-UE4SS/issues/) — the marshaler expects a UStruct-backed table on its own type stack, not a Lua-side `{}`. Constructing one from Lua isn't supported in v3.0.1.

The combined effect is that *no* documented Lua-side call shape works for the `(Bool out, X out)` signature class on `PMPlayerModel`. The UFunction itself is callable from Blueprint and from C++ — UE4SS is the failing layer, not UE.

For sibling cases that *do* work in this build (e.g. `PMIdentitySubsystem:GetSteamId()` returning a single output), the problem doesn't reproduce — single-output UFunctions go through a different (working) marshaling path. The failure is specific to the multi-output shape.

## Fix

> **2026-04-25 update**: The original "there is no Lua-side fix" conclusion is wrong for the call-shape question — the `({}, {})` empty-tables shape works on UE4SS 3.0.1. See `ue4ss-ufunction-out-param-marshaling-3-0-1.md` for the canonical fix and a copy-pasteable code example. **Try that first** before reaching for the workaround paths below. The workarounds remain valid as fallbacks if the `({}, {})` shape fails for an orthogonal reason on a specific UFunction.

The three original workaround paths (now fallbacks rather than primary recommendations), in increasing build cost:

1. **Direct property read** *(untested, plausible)*. Many UE games back `GetCached*` UFunctions with a UProperty field on the same UObject (e.g., `PMPlayerModel.CachedMeResponse : MeResponseV1` or similar). UE4SS exposes UProperty reads through `obj.PropertyName` without going through the UFunction marshaler. A property-dump probe on `PMPlayerModel` would identify whether such a field exists; if it does, this is a zero-build-cost workaround. **Deferred** — not needed for the current Stage-5 path (R-B's natural-login-fire cold start is sufficient), but worth a single-probe pass when the next feature wants synchronous cache reads.
2. **BP wrapper that calls the UFunction internally.** A Blueprint actor (delivered via `BPModLoaderMod`, per `mod-actor-pattern.md`) can call `GetCachedMeResponseV1` through Blueprint's native UFunction resolution — which doesn't go through UE4SS's Lua marshaler at all — and forward the `(WasCached, MeResponse)` payload back to Lua via a watched property or a notification UFunction Lua hooks. Same substrate ADR 0001's R-B already commits to for the delegate bridge; adds one more BP UFunction.
3. **UE4SS upgrade.** If a later UE4SS release fixes the `(Bool out, X out)` marshaling path, the original Lua-side call becomes viable again. Reopen this learning when an upgrade is attempted; verify with a fresh probe before assuming the fix applies.

For the current ADR 0001 / Stage-5 path, the chosen workaround is **none of the above** — R-B's revised cold-start posture removes the warm-cache pre-check entirely (wait for natural login fire). The workarounds above are documented for the next feature that needs synchronous cached reads (likely the remote-player profile cache for the wedge's "show another player's profile" surface).

## Lesson

**Three transferable insights:**

1. **For *any* UE4SS UFunction call from Lua, treat "the signature shows `(Bool out, X out)`" as a hard yellow flag.** This shape is broken across at least four UFunctions on `PMPlayerModel` in this build (three `GetCached*` reads + `GetMeV1` async request initiator); assume it's broken everywhere until proven otherwise on a per-call basis. The class of UFunction this affects is wide — anything named `TryGet*`, `GetCached*`, `IsValid*` (when paired with an out struct), AND any V1-style request initiator that returns `(WasSent: Bool, RequestId: Guid)` is suspect. When designing a feature around such a call, design the BP-wrapper escape hatch into the proposal *before* committing to a Lua-only path — don't discover it during the spike.
2. **A spike that probes a single UFunction is incomplete characterization of a UE4SS calling-convention question.** Pass-4 Rev-3 only probed `GetCachedMeResponseV1` and got "expected 2 parameters, received 0" — which initially looked like "maybe just need different args." Rev-4's three-UFunction × four-shape sweep took ~5 extra minutes and conclusively pinned the failure to the *signature shape*, not the call site. Always sweep two-or-more UFunctions of the same shape when characterizing a marshaling-layer behaviour; one is just an anecdote.
3. **The `os-runtime-data-model.md` calling-convention claim ("`(false, nil)` is the call shape") was a guess from the UFunction signature alone, not from a working call.** That guess survived from Pass-3 through to ADR 0001's first draft because it was *plausible* and had no in-game probe to falsify it. Lesson: a UE4SS calling-convention claim should not enter a learning doc until a working call exists. Mark such claims as "design-time guess, not validated" in the learning until the spike confirms — pre-spike R-B's confidence in the warm-cache pre-check would have been calibrated lower if this discipline had been applied earlier.

## Related

- **Supersedes (call-shape conclusion only):** [`ue4ss-ufunction-out-param-marshaling-3-0-1.md`](ue4ss-ufunction-out-param-marshaling-3-0-1.md) — the canonical UE4SS 3.0.1 multi-out-param call convention is `({}, {})`, empirically validated end-to-end via `PMIdentitySubsystem:GetAuthenticatedPlayerId` in OSPlus identity.lua v35→v36. Read that document first; treat this one as the failure-mode catalog and the per-shape error-message reference.
- **Spikes that produced this finding:** `docs/features/pass2-probes/pass2_probes.lua` — Pass 4 Rev-4, F8 keybind, `d2CacheFetch()` (the three-UFunction `GetCached*` sweep) AND Pass 5 step 2, F6 keybind, `probeE3()` (the `GetMeV1` force-trigger attempt that confirmed the bug extends to non-cache request initiators).
- **Probe log artifact:** `F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log` (not committed; reproducible by running the probe in-game).
- **ADR consuming this finding:** `docs/decisions/0001-identity-model.md` — pivots R-B's cold-start path from "warm-cache pre-check via UFunction" to "wait for natural login fire" because of this finding; documents the workaround paths in *Revisit triggers* and *Stage-5 prerequisite outcome*.
- **Sibling Pass-4 finding:** `docs/learnings/ue4ss-lua-multicast-delegate-binding.md` — the delegate-subscription substrate (D1) was the other half of the spike. D1 is viable with ModActor cost; D2 (this learning) is not viable in Lua. Both shape Stage-5 path together.
- **Updates to:**
  - `docs/learnings/os-runtime-data-model.md` — pre-spike claim that `(false, nil)` is the working call shape is falsified; that doc was edited in the same branch to point here.
  - `KNOWLEDGEBASE.md` → *Per-match runtime data* / *Player Identity Reference* — same correction.
- **Reference substrate (workaround #2):** `.cursor/skills/ue4ss-modding/references/mod-actor-pattern.md` — the BP-wrapper-for-UFunctions pattern.
- **UE4SS version pin:** v3.0.1, the version shipped with the OSPlus dev environment as of 2026-04-25. Re-test after any UE4SS upgrade.
