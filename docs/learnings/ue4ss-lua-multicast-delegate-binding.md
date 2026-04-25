# ue4ss-lua-multicast-delegate-binding

| Field | Value |
|---|---|
| Date | 2026-04-25 |
| Area | re |
| Tags | ue4ss, lua, delegates, multicast-delegate, modactor, native-crash, introspection |
| Status | confirmed |

## Symptom

Pass-4 spike for ADR 0001 (`docs/decisions/0001-identity-model.md`) attempted to subscribe to a UE multicast delegate (`PMPlayerModel.GetMeRequestV1Completed`, a `MulticastInlineDelegateProperty`) from UE4SS Lua. Three independent failure modes were hit in sequence:

1. **Native C++ access violation, no Lua-level error.** Calling `prop:Add(luaFunction)` crashed Omega Strikers immediately. `pcall` did not catch it. UE4SS log was overwritten by `CrashReportClient.exe` post-crash, so the killer call was invisible without out-of-process logging.
2. **False-friend method discovery.** Initial introspection assumed `getmetatable(prop)` would expose available methods. UE4SS hides the metatable (returns `false`), and `prop.AnythingYouAskFor` returns a `userdata` placeholder rather than `nil` for unknown keys — so naïve "if `prop.Bind` exists, call it" probes look successful for *every* guessed method name. Multiple wrong APIs (`Add`, `Bind`, `AddDynamic`) all appeared "available" pre-spike.
3. **Probe-induced crashes during early dev iterations.** Auto-binding from `LoopAsync` at script load crashed the game during launch (game-state not yet stable when the script ran). Manual `print()` logging was lost when the crash report tool overwrote UE4SS log files.

The compounding effect: on a UE4SS API that's lightly documented and where the `__index` doesn't fail loudly for unknown keys, every guess looks plausible until something native-crashes the host process.

## Root cause

**`MulticastDelegateProperty:Add` takes `(UObject targetObject, FName | string functionName)`, *not* a Lua function.** Per the [UE4SS docs](https://docs.ue4ss.com/dev/lua-api/classes/multicastdelegateproperty.html) and confirmed by [PR #1073 — *Lua: Delegate support* (merged Nov 2025)](https://github.com/UE4SS-RE/RE-UE4SS/pull/1073), the delegate's storage is a list of `(UObject, FName)` tuples that the engine fires by looking up the named UFunction on the target object. Passing a Lua function as `targetObject` causes the engine to dereference a Lua-runtime pointer as a `UObject*` — a native access violation by definition, with no Lua frame to report into. `pcall` cannot catch it because the violation happens below the Lua VM.

Three secondary facts compounded the discovery cost:

1. **UE4SS's `MulticastDelegateProperty` userdata `__index` returns a placeholder `userdata` for any key, not `nil`.** Only six names actually resolve to real Lua `function` types and are therefore safe to call: `Add`, `Remove`, `Clear`, `Broadcast`, `GetFName`, `GetClass`. Every other guessed name (`Bind`, `AddDynamic`, `AddUnique`, `On*`, etc.) returns a userdata that looks like a method but isn't. Pre-spike code that did `if prop.Bind then prop:Bind(cb) end` would happily call into a native garbage pointer — same crash class.
2. **`getmetatable(ud) == false`** for UE4SS userdata. Conventional metatable introspection is dead. The only working introspection is "iterate a list of likely method names and check if `type(ud[name]) == 'function'`" — read-only, no calls. The Pass-4 Rev-4 probe used this technique to discover the six real methods empirically.
3. **`pcall` does not catch native access violations** from UE objects. Combined with the crash report tool overwriting `UE4SS.log` post-crash, this means *any* probe that touches an unknown native API needs out-of-process persistent logging (with explicit `flush()` per write) or every step before the killer call is lost. Pre-spike `print(">>> ATTEMPT ...")` lines were *not* recovered after crashes; only the file-based `flog()` helper (write + flush + close per call) survived.

## Fix

**The right way to bind to a UE multicast delegate from UE4SS Lua:**

```lua
-- 1. Spawn or acquire a UObject (typically a ModActor BP delivered via BPModLoaderMod)
--    that exposes a UFunction matching the delegate's signature.
local modActor = -- ... acquire BP_OSPlusDelegateBridge instance

-- 2. The BP class must declare a UFunction (e.g. "OnMeResponse") whose signature
--    exactly matches MeRequestV1Completed__DelegateSignature:
--      (Succeeded: Bool, RequestId: Str, MeResponse: MeResponseV1, ErrorResponse: ErrorResponse)

-- 3. Bind from Lua:
local model = FindFirstOf("PMPlayerModel")
local prop = model.GetMeRequestV1Completed
prop:Add(modActor, "OnMeResponse")  -- (UObject, FName-or-string)

-- 4. The BP forwards the payload back into Lua via whatever bridge mechanism
--    the project chose (UE4SS RegisterHook on a notification UFunction the BP
--    calls, watched property the Lua side reads, etc.). See mod-actor-pattern.md.
```

**Anti-patterns that look right but native-crash the host process:**

```lua
prop:Add(function(...) end)            -- CRASH: Lua function is not a UObject
prop:Bind(function(...) end)           -- CRASH: prop.Bind returns a userdata
                                       --        placeholder, not a real method
prop:AddDynamic(self, function(...) end) -- CRASH: same as above
RegisterCustomEvent("FakeName", cb)     -- not the right tool — for hooks, not
                                       --        delegate subscriptions

-- pcall around any of these does NOT save you. The crash is below the Lua VM.
```

**Introspection technique that's safe** (no method calls, only key-type reads):

```lua
local LIKELY = { "Add", "Remove", "Clear", "Broadcast", "GetFName", "GetClass",
                 "Bind", "Unbind", "AddDynamic", "AddUnique", -- false friends
                 "On", "Register", "IsBound", "Contains", -- more false friends
                 -- ...add any name you'd guess
               }
for _, name in ipairs(LIKELY) do
    local v = prop[name]
    print(string.format("  %s -> %s", name, type(v)))
end
-- Real methods report as "function". Everything else reports as "userdata"
-- — those are __index placeholders, NOT safe to call.
```

**Crash-survivable logging pattern** (every probe touching an unfamiliar native API should use this):

```lua
local PROBE_LOG_PATH = "OSPlusProbes.log"  -- ends up in Binaries/Win64/
local function flog(msg)
    print(msg)
    pcall(function()
        local f = io.open(PROBE_LOG_PATH, "a")
        if f then
            f:write(string.format("[%s] %s\n", os.date("%H:%M:%S"), msg))
            f:flush()  -- critical — without flush, last buffer is lost on crash
            f:close()
        end
    end)
end
flog("[D1] step 1 >>> ATTEMPT property access")  -- log BEFORE every native call
```

## Lesson

**Three transferable insights, in priority order:**

1. **`MulticastDelegateProperty:Add(target, fname)` is the API; passing a Lua function is a native crash.** Any UE4SS Lua delegate-binding code in this codebase must route through a UObject (in practice: a ModActor BP delivered via `BPModLoaderMod`, per `.cursor/skills/ue4ss-modding/references/mod-actor-pattern.md`). This is *not* a UE4SS limitation — it's how UE delegates work natively; UE4SS is exposing the underlying engine API faithfully. The cost is one BP class per delegate signature.
2. **For unknown UE4SS userdata, do not trust `if ud.MaybeMethod then` — `__index` returns userdata placeholders for unknown keys, not `nil`.** The only safe API discovery is `type(ud.name) == "function"`. The placeholder problem is what made pre-spike "I'll just try `prop:Bind` first and fall back to `prop:Add`" appear to be a thoughtful guard but actually a guaranteed second crash if `Add` failed. Apply this rule to *every* unfamiliar UE4SS userdata, not just `MulticastDelegateProperty`.
3. **For any spike that touches an unfamiliar native API, write a `flog()` helper with `flush()` per call before doing anything else.** `print()` is not enough — when the game crashes, `CrashReportClient.exe` overwrites `UE4SS.log` and your stdout history is gone. This was the difference between Rev-2 (lost the killer call to log clobber) and Rev-3 (pinpointed the killer call exactly to one `flog` line). The cost is ~10 lines of Lua. Pay it on every native-RE probe.

A meta-point: **discovery probes should be keybind-driven, never auto-running at script load.** Rev-1 of the Pass-4 probe auto-bound at load and crashed the game during launch — debugging that required disabling the mod entirely. F8/F9-driven probes only crash when the developer asks them to, which is a much more controllable iteration loop.

## Related

- **Spike that produced this finding:** `docs/features/pass2-probes/pass2_probes.lua` (Pass 4 — F8 keybind, four iterative revisions).
- **Probe log artifact:** `F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log` (not committed; reproducible by running the probe).
- **ADR consuming this finding:** `docs/decisions/0001-identity-model.md` — uses the documented binding API as R-B's substrate.
- **Sibling Pass-4 finding:** `docs/learnings/ue4ss-outparam-marshaling-failure.md` — the other half of the spike (cache-pre-check substrate availability) failed for an unrelated reason; both findings together shape the revised R-B implementation path.
- **Updates to:** `docs/learnings/os-runtime-data-model.md` — pre-spike claim ("`(false, nil)` is the call shape") was a calling-convention guess that was falsified; that doc was edited in the same branch to point at this learning rather than re-derive the wrong shape.
- **Reference substrate:** `.cursor/skills/ue4ss-modding/references/mod-actor-pattern.md` — the BP-actor-from-Lua pattern that the binding now requires.
- **Upstream sources:**
  - [UE4SS docs — `MulticastDelegateProperty`](https://docs.ue4ss.com/dev/lua-api/classes/multicastdelegateproperty.html) — official `Add(target, fname)` signature.
  - [UE4SS PR #1073 — *Lua: Delegate support* (merged Nov 2025)](https://github.com/UE4SS-RE/RE-UE4SS/pull/1073) — the PR that landed the delegate API in the form this codebase uses.
