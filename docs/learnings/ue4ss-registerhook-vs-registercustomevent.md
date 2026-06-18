# UE4SS 3.0.1: `RegisterHook` for native UFunctions, `RegisterCustomEvent` for pure BP

| Field | Value |
|---|---|
| Date | 2026-05-16 |
| Area | ue4ss |
| Tags | ue4ss-3.0.1, register-hook, register-custom-event, bp-functions, hooking, func-native |
| Status | confirmed |

## Symptom

Tried to hook a Widget Blueprint UFunction (`WBP_Panel_StrikerCosmetics_C:SetActivePanel`) via the existing `RegisterHook` pattern that works elsewhere in OSPlus (chat.lua hooks `OnRep_MatchState`, identity.lua hooks `PMIdentitySubsystem:GetIdentityState`). Got this error:

```
Was unable to register a hook with Lua function 'RegisterHook', information:
FunctionName: /Game/Prometheus/UI/OutOfGame/Strikers/WBP_Panel_StrikerCosmetics.WBP_Panel_StrikerCosmetics_C:SetActivePanel
UFunction::Func: 0x0
ProcessInternal: 0x7ff6f43b82d0
FUNC_Native: 0
```

Initially mistook this for a timing problem (class not loaded) and added a NotifyOnNewObject deferral. The error persisted because the issue is not timing — it's the function's nature.

## Root cause

`RegisterHook` in UE4SS 3.0.1 hooks UFunctions by replacing the native function pointer (`UFunction::Func`) with a trampoline. Pure BP UFunctions have a null `Func` pointer — their body is Kismet bytecode executed by `UObject::ProcessInternal`, not a callable native function. `FUNC_Native: 0` in the error literally tells you the function has no native implementation; there is nothing for RegisterHook to swap. This is documented behavior, not a bug.

## Fix

Use **`RegisterCustomEvent`** instead. It hooks at the `ProcessInternal` dispatch level — UE4SS intercepts every BP VM dispatch and matches the called UFunction's short name against registered callbacks. Class-agnostic (matches by name globally; filter inside the callback if needed). Works for any pure BP UFunction.

**API surface (3.0.1):**

```lua
RegisterCustomEvent("SetActivePanel", function(Context, ParamA, ParamB)
    -- Context:get() returns the calling UObject instance
    -- ParamA, ParamB, ... are Param wrappers; use :get() / :set(new)
    local self_ = Context:get()
    local cls = self_:GetClass():GetFName():ToString()
    -- Filter to our target class — short-name match catches any class
    if cls ~= "WBP_Panel_StrikerCosmetics_C" then return end

    local panel = ParamA:get()  -- unwrap the panel arg
    -- ... do something with self_ and panel ...
end)
```

**Critical timing gotcha:** RegisterCustomEvent fires **post-execution**. By the time your callback runs, the BP function has already executed with its original args. `param:set(newValue)` accepts the value but it's too late — the function won't run again with the new arg. **Param:set is observation-of-state, not argument-modification, in this context.**

To get redirect behavior (override what the function did), call the function again from your callback with the substituted args, guarded by a recursion flag:

```lua
local cachedReplacement = nil
local inRedirect = false

RegisterCustomEvent("SetActivePanel", function(Context, PanelParam)
    if inRedirect then return end  -- skip our own recursive calls

    local self_ = Context:get()
    if self_:GetClass():GetFName():ToString() ~= "WBP_Panel_StrikerCosmetics_C" then return end

    local panel = PanelParam:get()
    -- ... your substitution logic determines `wantedPanel` ...
    if panel ~= wantedPanel then
        inRedirect = true
        self_:SetActivePanel(wantedPanel)  -- recursive call with mutated arg
        inRedirect = false
    end
end)
```

The inner call re-runs the BP function with the substituted arg; its display work overrides the first run's display work. The recursion guard prevents the hook from re-entering on the inner call.

## API selection rule

| Function type | Detection | Hook API |
|---|---|---|
| Native (C++ implementation) | `FUNC_Native: 1`, `Func` pointer non-null | `RegisterHook(FullPath, preCb, postCb)` — pre and post both available |
| Pure BP (BP-only body) | `FUNC_Native: 0`, `Func` pointer null | `RegisterCustomEvent(ShortName, cb)` — post only, recursive-call for redirect |
| BP on class not yet loaded | RegisterHook fails with "no UFunction found" | Defer install via `NotifyOnNewObject` on the class path, then RegisterHook from inside the callback (only useful if the function is actually native — pure BP still needs RegisterCustomEvent) |

Pre-execution argument mutation is not generally available in UE4SS 3.0.1 Lua. Don't design override patterns around modifying args before the call; design them around recursive-call-after-the-call.

## Lesson

Three transferable rules:

1. **Read the error literally.** `FUNC_Native: 0` is the canonical signal that you're dealing with a pure BP UFunction. Don't iterate on the timing (deferred install via NotifyOnNewObject) when the issue is the API itself. Switch to RegisterCustomEvent and the same call instantly succeeds.

2. **RegisterCustomEvent matches by short name globally.** If the function name is common (`Construct`, `SetActivePanel`, `Tick`), every class that has a function with that name will fire your callback. Always filter inside: `Context:get():GetClass():GetFName():ToString()`. We caught this immediately because `WBP_Menu_Striker_C` *also* has a `SetActivePanel` for top-level tab routing — without the filter, our hook would also fire on parent-page activation.

3. **Hook callback timing is post-execution.** Plan override logic around "function ran, what do I do now" rather than "function is about to run, what do I change." For redirect behavior, call the function again from inside the hook with substituted args, recursion-guarded.

## Related

- Validating learning: [`docs/learnings/customize-page-tab-routing-architecture.md`](./customize-page-tab-routing-architecture.md) — the case study where this API choice was discovered the hard way
- UE4SS docs (canonical references):
  - https://docs.ue4ss.com/lua-api/global-functions/registercustomevent.html
  - https://docs.ue4ss.com/lua-api/global-functions/registerhook.html
  - https://docs.ue4ss.com/lua-api/global-functions/notifyonnewobject.html
- UE4SS issue tracker (matching symptom): https://github.com/UE4SS-RE/RE-UE4SS/issues/467
- Existing OSPlus modules using RegisterHook on natives (correct for those cases): `mod/OSPlus/scripts/chat.lua` (GameState:OnRep_MatchState), `mod/OSPlus/scripts/identity.lua` (PMIdentitySubsystem:GetIdentityState)
