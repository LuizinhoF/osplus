# ue4ss-multicast-delegate-add-silent-noop

| Field | Value |
|---|---|
| Date | 2026-04-25 |
| Area | re |
| Tags | ue4ss, lua, delegates, multicast-delegate, vtable, silent-failure, prometheus, register-hook |
| Status | confirmed |

## Symptom

Pass-5 spike for ADR 0001 attempted to validate the R-B path's substrate (event-driven identity via the ModActor BP wrapper that Pass-4 had documented). On this UE4SS build, calling `prop:Add(uobject, fname)` on a `MulticastInlineDelegateProperty` from Lua returns ok with no error — but **does not actually register an engine-side binding**. Every downstream observation that should have signalled "binding present" reports zero:

1. **`prop:Add(modActor, "OnMeResponseFired")` returns ok** with no error, no warning, no log entry indicating failure. Identical behavior for `prop:Add(model, "FakeNonExistentName")` — fully permissive at the bind-time validation layer (no `FindFunction` check). This much is consistent with the documented `Add(UObject, FName)` signature from `docs/learnings/ue4ss-lua-multicast-delegate-binding.md`; the failure is downstream.
2. **`prop:GetBindings()` returns 0 binding(s)** after every `Add` call. Tested in F1/E8 v2 across 5 sequential Add/Remove/Add cycles — every cycle reports 0.
3. **`prop:Broadcast(false, "test-id", nil, nil)` succeeds at the marshaling layer** (UE4SS reports OK — args accepted by the `LuaXDelegateProperty.cpp` `push_*` shape-validators) — the call goes through to `ProcessMulticastDelegate<void>` dispatch — **but our `RegisterHook` on the bound target UFunction does not fire**. Confirmed against a `RegisterHook(/Game/Mods/OSPlus/ModActor.ModActor_C:OnMeResponseFired)` that UE4SS's log explicitly reported as `Registered script hook (NN, NN) for Function …`. The hook is real; the InvocationList that should drive it is empty.
4. **F2/E7 broadcast-bind to all 40 `PMPlayerModel` multicast delegates produced 0 hook fires** across ~50s of UI nav including a loadout-character mutation — independent confirmation that natural engine-side broadcasts also find nothing in our binding list.

The four signals together make the diagnosis airtight: **the only callable Lua API for binding to a `MulticastInlineDelegateProperty` is a no-op on this UE4SS build, for any combination of (target object, function name, FName-vs-string FName, same-actor-vs-cross-actor target).**

The Pass-5 Phase-D triangulation probe (`F10` / E8.D in `docs/features/pass2-probes/pass2_probes.lua`) ran six independent sub-tests to rule out shape-specific causes:

- **D0 — UClass introspection.** `prop:GetClass():GetFName():ToString() == "MulticastInlineDelegateProperty"` confirmed; not a misidentified `Sparse` or regular `Multicast`.
- **D1 — `pairs(prop)` iteration.** Errored ("userdata not iterable"). No internal Lua-side `InvocationList` surface.
- **D2 — API surface enumeration.** Exactly **6 callables** exposed for this property type: `Add`, `Remove`, `Clear`, `Broadcast`, `GetBindings`, `IsValid`. No `AddDynamic`, no `AddUFunction`, no `Bind`, no `BindUObject`, no `AddRaw`, no `AddLambda` — there is **no alternate API name** to fall back to.
- **D3 — same-actor bind.** `prop:Add(model, "GetMeV1")`, `prop:Add(model, "GetDisplayNameV1")`, `prop:Add(model, "GetCachedMeResponseV1")` — all three reported `ok=true` and `bindings 0→0 Δ=0`. **The no-op is universal**, not a cross-actor specific issue.
- **D4 — explicit `FName(...)` bind.** `prop:Add(modActor, FName("OnMeResponseFired"))` — same `ok=true`, same `Δ=0`. Not a string→FName conversion bug.
- **D5 — `:Bind()` alternate API.** `prop.Bind` is not a callable function on this UClass. Single-cast API not exposed for multicast.
- **D6 — cross-actor re-confirmation.** Reproduces F1 v2's verdict deterministically: `Add` returns ok, `GetBindings` stays 0, `Broadcast(arity 4)` succeeds at marshaling but produces 0 hook fires.

## Root cause

Most likely: **vtable-offset mismatch in UE4SS's binary parser for Omega Strikers' `FMulticastInlineDelegateProperty` layout.**

The actual `Add` implementation in [PR #1073](https://github.com/UE4SS-RE/RE-UE4SS/pull/1073) (`UE4SS/src/LuaType/LuaXDelegateProperty.cpp`, the only commit that introduced these Lua bindings — merged 2025-11-06) is simple and correct on its face:

```cpp
table.add_pair("Add", [](const LuaMadeSimple::Lua& lua) -> int {
    const auto& lua_object = lua.get_userdata<XMulticastDelegateProperty>();
    auto* property  = lua_object.m_property;
    auto* container = lua_object.m_base;

    auto* target_object = lua.get_userdata<UObject>(1).get_remote_cpp_object();

    Unreal::FName fname;
    if (lua.is_string(1)) {
        fname = Unreal::FName(to_wstring(lua.get_string(1)), Unreal::FNAME_Add);
    } else {
        fname = lua.get_userdata<FName>(1).get_local_cpp_object();
    }

    Unreal::FScriptDelegate script_delegate;
    script_delegate.BindUFunction(target_object, fname);

    void* property_value = property->ContainerPtrToValuePtr<void>(container);
    property->AddDelegate(script_delegate, container, property_value);
    return 0;
});
```

Two relevant facts about this code:

1. **`FScriptDelegate::BindUFunction(target, fname)` is validation-free** — it only stores `(WeakObjectPtr, FName)`. No `FindFunction` lookup at bind time. This is how `Add(modActor, "AnyFakeName")` returns ok — the engine doesn't validate the name until *dispatch*, at which point it's already too late to surface an error to the caller.
2. **`AddDelegate` is invoked via the property's vtable.** UE4SS resolves it through `assets/VTableLayoutTemplates/VTableLayout_4_27_Template.ini`, which lists `AddDelegate`/`RemoveDelegate`/`ClearDelegate`/`GetMulticastDelegate` for `FMulticastDelegateProperty`. **If UE4SS's binary-parser pass over Omega Strikers' shipped game executable misidentifies the offset for any of these slots, `AddDelegate` may resolve to `ClearDelegate` or to a no-op slot.** The Lua-side never sees an error because the call still resolves to *some* virtual member of `FMulticastDelegateProperty`.

That single failure mode explains every symptom we observed:

- `Add` succeeds (call dispatches via vtable, regardless of which slot)
- `GetBindings` returns 0 (correctly reflects the empty `InvocationList`, because the binding never landed)
- `Broadcast` succeeds at marshaling but invokes nothing (correctly iterates an empty `InvocationList`)
- Natural engine-side broadcasts also find nothing in our list (same empty list)

PR #1073 has **no regression tests** for inline-multicast on a custom `UObject` subclass with a packaged-game `__DelegateSignature` from a non-engine namespace (our exact case: `/Script/Prometheus.MeRequestV1Completed__DelegateSignature` on `UDataModel` subclass `PMPlayerModel`). The PR is ~5 months old in production. We may be the first hitting this exact failure mode.

Other plausible-but-less-likely causes the web research considered:

- **`m_base` pointer mismatch** — `XMulticastDelegateProperty(const PusherParams& params) : m_base(params.base)` — if `model` is a wrapped/proxied `UDataModel` reference (`TWeakObjectPtr`-style indirection in Prometheus), `ContainerPtrToValuePtr<void>(container)` computes the delegate value at a different address than where the engine reads from. Less likely because we're reading the same property via the same path consistently — but possible.
- **`FMulticastInlineDelegateProperty` vs `FMulticastDelegateProperty` cast on a non-layout-compatible subclass** — Prometheus may declare the property in a non-standard subclass that reports its FName as `MulticastInlineDelegateProperty` but isn't binary-compatible with what UE4SS casts to. Undefined behavior at the cast site. Also less likely; this would typically manifest as a crash, not a silent no-op.

The vtable hypothesis is strongest because (a) it cleanly explains all four symptoms with no contortion, (b) it's the failure mode the source-level researcher specifically called out, and (c) it's a known class of UE4SS issue (the vtable-layout file is per-engine-version and parsed against per-game binaries; mismatches manifest as silent virtual-call mis-dispatch).

The orthogonal Issue [#483](https://github.com/UE4SS-RE/RE-UE4SS/issues/483) ("RegisterHook does not work with delegate functions") is **not** what we're hitting. That issue is about hooking the `__DelegateSignature` UFunction directly; we're hooking a regular UFunction (`OnMeResponseFired`) on a BP class. If a binding existed on the multicast delegate, `Broadcast` → `ProcessEvent` → our hook chain would fire. The empty `InvocationList` is the issue, not the hook chain.

## Fix

**Stop using `prop:Add` for cross-actor BP↔Lua signaling on this UE4SS build.** The maintainer-recommended workaround for exactly this scenario, documented in [Issue #455](https://github.com/UE4SS-RE/RE-UE4SS/issues/455), is:

> **`NotifyOnNewObject` + `RegisterHook` on the *originating* function** — instead of subscribing to the multicast delegate, hook the engine function that *calls* `Broadcast` on it (typically the Prometheus-side request-handling code that fires `GetMeRequestV1Completed`). This is the most reliable cross-actor pattern in UE4SS today.

Concretely, for the OSPlus identity path:

```lua
-- Before (R-B as designed in ADR 0001, pre-Pass-5):
--   1. Spawn ModActor BP via BPModLoaderMod
--   2. ModActor BP exposes UFunction matching delegate signature
--   3. prop:Add(modActor, "OnMeResponseFired")  -- silent no-op on this build
--   4. Wait for engine to invoke the bound UFunction (never happens)

-- After (R-B revised, Pass-5 pivot):
--   1. RegisterHook on a Prometheus-side UFunction that fires during identity flow.
--      Exact target identified via Pass-6 RegisterHook discovery probe; candidates
--      include PMPlayerModel:GetMeV1 (the request initiator) and downstream
--      callbacks discoverable by hooking each of PMPlayerModel's 44 UFunctions
--      and observing which fire during natural login.
--   2. Inside the hook callback, read identity state from `self`
--      (the PMPlayerModel UObject) which is fully populated by the time
--      the originating function fires.
--   3. No BP work, no ModActor wrapper, no delegate binding API involvement.

RegisterHook("/Script/Prometheus.PMPlayerModel:GetMeV1", function(context)
    local model = context:get()
    -- read identity from model.* properties, emit identity event
end)
```

Why this works when delegate binding doesn't:

- **`RegisterHook` is implemented by patching the UFunction's `Func` pointer to UE4SS's interceptor**, not via vtable dispatch on a `UProperty`. Different code path; no exposure to the vtable-layout misidentification that breaks `AddDelegate`.
- **The originating function fires synchronously at the moment the engine invokes it**, with `self` already populated with the PMPlayerModel state we need. No BP bridge needed.
- **`RegisterHook` substrate is proven on this UE4SS build** — Pass-5 F6 confirmed `Registered script hook (NN, NN) for Function /Game/Mods/OSPlus/ModActor.ModActor_C:OnMeResponseFired`. The hook registration succeeded; only the call-graph-from-Broadcast was missing.

**Other workarounds the research surfaced** (recorded for future reference, not used in OSPlus):

- **`RegisterHookFromBP`** ([PR #421](https://github.com/UE4SS-RE/RE-UE4SS/pull/421)) — register hooks from the BP side instead of from Lua. Bypasses the Lua delegate API, but requires BP work that the Lua-side `RegisterHook` workaround doesn't.
- **UE4SS C++ mod** — write a native UE4SS mod that calls `FMulticastDelegateProperty::AddDelegate` via the engine API directly, bypassing the Lua layer's vtable indirection. Highest fidelity to the original design, highest engineering cost (separate build pipeline, more fragile to UE4SS version changes).
- **Direct property-pointer manipulation from Lua** — read/write the delegate's `InvocationList` field directly. Last-resort hack; not portable across engine versions; not viable on this build because `pairs(prop)` doesn't expose `InvocationList` as an iterable field anyway.

## Lesson

**Three transferable insights, in priority order:**

1. **For any UE4SS Lua delegate-binding work on a packaged-game (non-engine-namespace) property, validate end-to-end before designing on top of it.** Pass-4 stopped at "the documented API exists and accepts our call shape" — that was sufficient for the ADR's "API surface" question but insufficient for "the API actually works on this game's binary." A 2-line follow-up probe (`Add` → `GetBindings`) would have caught this immediately. Going forward: any spike that depends on a UE4SS Lua API method against a non-engine-namespace property must include a `GetBindings`-style observable-state check before declaring substrate viable.

2. **For cross-actor BP↔Lua signaling, prefer `RegisterHook` on the originating engine UFunction over delegate subscription via the Lua `Add` API** — this is the maintainer-recommended pattern (Issue [#455](https://github.com/UE4SS-RE/RE-UE4SS/issues/455)) and the strictly cheaper one (no BP wrapper, no cook step, no Lua-BP bridge). The delegate-binding API only really shines when you have a fully-functional `Add` substrate AND the BP-side authoring cost amortizes across many delegates; on this build neither holds.

3. **A "succeeds but does nothing" failure mode in a virtual-method-dispatch API is the signature of a vtable-offset mismatch** — when an API call returns ok with no error, but every observable downstream signal contradicts the success, the most likely cause is that the call resolved to the wrong virtual slot. UE4SS's vtable-layout files are per-engine-version and parsed against per-game binaries; mismatches are silent. Diagnostic tactic: read back observable state via a *different* method than the one you wrote with (e.g. `Add` then `GetBindings`); if one says "yes" and the other says "no", suspect vtable.

A meta-point: **the Phase-D triangulation probe was decisive in <1min of game time** — it tested 6 independent variations of the failing API in a single Lua probe with structured per-variation logging, eliminating shape-specific causes (cross-actor, FName conversion, alt API name, Sparse vs Inline) with minimal experimental cost. The pattern of "run a battery of small variations in one probe rather than serializing them across multiple game restarts" generalizes — when a substrate is failing for unknown reasons and the next-step has high architectural cost, invest in a triangulation probe before pivoting. The cost is one Lua probe; the value is "we don't pivot to UE4SS C++ mod when same-actor bind would have worked."

## Related

- **Spike that produced this finding:** `docs/features/pass2-probes/pass2_probes.lua` (Pass 5 — F6/E3, F4/E5, F3/E6, F2/E7, F1/E8, F10/E8.D probes).
- **Probe log artifact:** `F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log` (not committed; reproducible).
- **Sibling Pass-4 finding (now partially superseded):** `docs/learnings/ue4ss-lua-multicast-delegate-binding.md` — documents the *correct* API surface (`prop:Add(uobject, fname)`, false-friend trap, crash-survivable logging). Still valid for any delegate work that *does* succeed at substrate; **but no longer load-bearing for ADR 0001's R-B path**, because the API is non-functional on this build for the property type we need.
- **ADR consuming this finding:** `docs/decisions/0001-identity-model.md` — R-B path was designed around the (now non-functional) `prop:Add` substrate and pivots to `RegisterHook` per this learning's *Fix* section.
- **Sibling Pass-4 finding still load-bearing:** `docs/learnings/ue4ss-outparam-marshaling-failure.md` — the `(Bool out, X out)` UFunction-marshaling block remains in effect; affects which UFunctions the Pass-6 RegisterHook probe can usefully introspect (`self`-side reads only, no Lua-issued out-param calls).
- **Upstream sources:**
  - [UE4SS PR #1073 — *Lua: Delegate support* (merged 2025-11-06)](https://github.com/UE4SS-RE/RE-UE4SS/pull/1073) — the PR that introduced `prop:Add`/`Broadcast`/`GetBindings`/`IsValid`. Contains the source code quoted under *Root cause*.
  - [`UE4SS/src/LuaType/LuaXDelegateProperty.cpp`](https://raw.githubusercontent.com/UE4SS-RE/RE-UE4SS/main/UE4SS/src/LuaType/LuaXDelegateProperty.cpp) — current `main` source for `Add`/`Remove`/`Clear`/`Broadcast`/`GetBindings`/`IsValid` (no follow-up fixes since PR #1073).
  - [`assets/VTableLayoutTemplates/VTableLayout_4_27_Template.ini`](https://raw.githubusercontent.com/UE4SS-RE/RE-UE4SS/main/assets/VTableLayoutTemplates/VTableLayout_4_27_Template.ini) — the vtable layout file that may misidentify `AddDelegate`'s offset for Omega Strikers' shipped binary.
  - [Issue #455 — BP-mod-loader + Lua delegate workaround](https://github.com/UE4SS-RE/RE-UE4SS/issues/455) — maintainer-recommended pattern: hook the originating function instead of subscribing to the delegate.
  - [Issue #483 — `RegisterHook` does not work with `__DelegateSignature` UFunctions](https://github.com/UE4SS-RE/RE-UE4SS/issues/483) — adjacent (different mechanism), explicitly **not** what we hit; recorded here so a future agent doesn't conflate the two.
  - [PR #682 — docs warning for Issue #483](https://github.com/UE4SS-RE/RE-UE4SS/pull/682).
  - [PR #421 — `RegisterHookFromBP`](https://github.com/UE4SS-RE/RE-UE4SS/pull/421) — alternative workaround for BP-side hook registration.
  - [Epic forums — `BindUFunction` silent failure semantics](https://forums.unrealengine.com/t/unable-to-bind-delegate-function-might-not-be-marked-as-a-ufunction/359016) — confirms the validation-free behavior of `FScriptDelegate::BindUFunction`.
- **Reference substrate (no longer required for R-B):** `.cursor/skills/ue4ss-modding/references/mod-actor-pattern.md` — the BP-actor-from-Lua pattern Pass-4 envisioned for R-B's bridge. Still valid as a substrate for *other* features that genuinely need a BP-side actor; not load-bearing for ADR 0001 anymore.
