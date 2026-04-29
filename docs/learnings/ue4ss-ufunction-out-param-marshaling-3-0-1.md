# ue4ss-ufunction-out-param-marshaling-3-0-1

| Field | Value |
|---|---|
| Date | 2026-04-25 |
| Area | re |
| Tags | ue4ss, lua, ufunction, out-params, marshaling, calling-convention, prometheus, identity |
| Status | `confirmed` (empirically validated against UE4SS 3.0.1, Omega Strikers shipping branch) |
| UE4SS version | 3.0.1 (the version OSPlus ships against; re-validate on any upgrade) |

## Symptom

UE4SS reflection exposes UFunctions like `PMIdentitySubsystem:GetAuthenticatedPlayerId(Valid: BoolProperty, OutPlayerId: StrProperty)` — both parameters declared as **out-params** in the engine's UFunction signature. Calling these from Lua looks easy on paper but is not: every "obvious" C++-flavored call shape errors at the marshaling layer with one of two distinctive messages.

The full failure ladder, all observed against this exact UFunction:

| Call shape | Error |
|---|---|
| `inst:GetAuthenticatedPlayerId()` | `[UFunction::setup_metamethods -> __call] UFunction expected 2 parameters, received 0` |
| `inst:GetAuthenticatedPlayerId(false, "")` (primitives as placeholders) | `Tried storing reference to a Lua table for an 'Out' parameter when calling a UFunction but no table was on the stack` |
| `inst:GetAuthenticatedPlayerId(false, nil)` | `UFunction expected 2 parameters, received 1` (the trailing `nil` is dropped by Lua before reaching the marshaler) |
| `inst:GetAuthenticatedPlayerId({}, {})` (the working shape) | **Succeeds.** The first table is populated with `{Valid = true, OutPlayerId = <FString userdata>}`. The second table stays empty (UE4SS 3.0.1 collapses both base-type out-params into the first bucket). |

The second-row error is the diagnostic that points at the right answer — UE4SS specifically says it expected a *table*, not a value. But "pass `nil`" is the most-quoted "obvious" fix in stale forum posts (which are usually about C++-style ref params, not UE4SS Lua), and it errors with a message that *looks* like the symptom of the first row, masking the real fix until you read the wording carefully.

The cost when this isn't documented: **three iterations across two days** to derive the empty-table convention by elimination. v33 stopped at "expected 2 received 0", v34 retried with primitive placeholders and hit the "no table on the stack" error, v35 finally landed `({}, {})`. Each iteration cost a full game-restart loop with the user.

## Root cause

UE4SS marshals UFunction out-parameters by treating Lua tables as the only **by-reference container type Lua provides** — the marshaler writes results into a caller-provided table after the call completes. There is no Lua equivalent for `bool& out` semantics; tables are the bridge.

Three rules combine to make the convention non-obvious from the C++ signature alone:

1. **Trailing `nil` is dropped before the marshaler sees it.** Lua's calling convention drops trailing `nil`s in vararg / table-unpack contexts; UE4SS counts what arrives, not what was written. So `Fn(x, nil)` reaches the marshaler as `Fn(x)` and bails with "expected 2 received 1." This rules out the "pass nils as placeholders" pattern that *seems* like the C++ analog.
2. **A primitive value in an out-param slot is rejected explicitly.** The marshaler error message is unambiguous: `Tried storing reference to a Lua table for an 'Out' parameter when calling a UFunction but no table was on the stack`. The "stack" here is UE4SS's value stack, not the Lua call stack. Passing `false`, `""`, `0`, etc. into an out-param slot triggers this even though those values are syntactically present.
3. **An empty table `{}` is the only accepted placeholder.** UE4SS uses the table as a by-reference container. After the call:
   - **Base-type out-params** (`Bool`, `Str`, `Int`, `Float`, `Name`, `Text`, `TMap`): UE4SS writes results into `bucket.<ParamName>`. So for `(Valid: Bool, OutPlayerId: Str)` you read `bucket.Valid` and `bucket.OutPlayerId`.
   - **Struct out-params**: the bucket table itself *becomes* the struct (no nested `.OutMyStruct` field). Read fields directly from the bucket: `bucket.PlayerId`, `bucket.Username`, etc.
   - **TArray out-params**: similarly, the bucket table becomes the array.

**UE4SS 3.0.1 specifically — multi-out-param collapse (Issue [#971](https://github.com/UE4SS-RE/RE-UE4SS/issues/971)):** when a UFunction declares multiple base-type out-params, UE4SS 3.0.1 writes **all of them into the FIRST bucket**, ignoring the rest. We empirically confirmed this in the v35 run:

```
[IDENTITY] [v35-outparam-probe] === GetAuthenticatedPlayerId post-call ===
[IDENTITY] [v35-outparam-probe] Lua returns: ret1=nil ret2=nil
[IDENTITY] [v35-outparam-probe] validBucket[OutPlayerId] = userdata{:ToString()="632680c154686dedd6522b09"}
[IDENTITY] [v35-outparam-probe] validBucket[Valid] = bool{true}
[IDENTITY] [v35-outparam-probe] pidBucket = {} (empty)
```

Both `Valid` and `OutPlayerId` landed in `validBucket`; `pidBucket` was empty. **You still have to pass the second `{}`** — without it the marshaler errors with `expected 2 received 1` — but you read both results out of bucket #1.

## Fix

**The canonical UE4SS 3.0.1 multi-out-param call pattern, copy-pasteable:**

```lua
local function readAuthenticatedPlayerId()
    local instance
    pcall(function() instance = FindFirstOf("PMIdentitySubsystem") end)
    if not instance or not instance:IsValid() then
        return nil, "subsystem-not-found"
    end

    -- Pass one empty table per declared out-param. UE4SS 3.0.1 collapses
    -- both base-type out-params into validBucket; pidBucket stays empty
    -- but is required for parameter-count matching (see Issue #971).
    local validBucket = {}
    local pidBucket = {}
    local ok, err = pcall(function()
        instance:GetAuthenticatedPlayerId(validBucket, pidBucket)
    end)
    if not ok then return nil, "call-errored:" .. tostring(err) end

    -- Defensive read: iterate buckets so a future UE4SS that splits the
    -- params correctly across buckets keeps working without code change.
    local function pluck(name, expectedType)
        for _, b in ipairs({validBucket, pidBucket}) do
            local v = b[name]
            if v ~= nil and (expectedType == nil or type(v) == expectedType) then
                return v
            end
        end
    end

    local valid = pluck("Valid", "boolean")
    if valid ~= true then return nil, "not-yet-authenticated" end

    local pidUd = pluck("OutPlayerId")
    -- Out-param string values come back as FString userdata; :ToString() unwraps.
    if type(pidUd) == "userdata" then return pidUd:ToString() end
    return pidUd  -- some shapes return a plain string
end
```

**Worked reference**: `mod/OSPlus/scripts/identity.lua` → `readAuthenticatedPlayerId` (production code, validated end-to-end against the running game).

**For struct out-params** (e.g., a hypothetical `GetCachedLoginResponse(Success: Bool, LoginResponse: LoginResponseV1)`): pass two buckets, but read the `LoginResponse` struct's fields *directly off* `respBucket` (not `respBucket.LoginResponse`):

```lua
local successBucket = {}
local respBucket = {}
instance:GetCachedLoginResponse(successBucket, respBucket)

local success = successBucket.Success     -- base type, lands in its own bucket
local sessionId = respBucket.SessionId    -- struct fields land directly on respBucket
local accountId = respBucket.AccountId
```

This struct-bucket-becomes-struct rule is documented in [Issue #920](https://github.com/UE4SS-RE/RE-UE4SS/issues/920); we've confirmed it for the bool-half (`successBucket.Success`) but not yet exercised any specific struct-out-param call to ground-truth that the struct half lands directly on the second bucket on UE4SS 3.0.1. Cross-reference the empty `pidBucket` finding above as a corollary: when the second bucket is *unused*, it stays empty rather than receiving the second base-type param. Whether that means the second bucket *is* the struct receiver for struct out-params, or whether 3.0.1 also collapses struct out-params somewhere else, is not yet validated. Probe before relying.

## Lesson

**Three transferable insights:**

1. **The UE4SS error message is the next-call-shape diagnostic.** "Expected N received M" tells you the parameter count problem. "Tried storing reference to a Lua table … no table on the stack" tells you the marshaler wanted a table at the position you sent a value. "Tried calling a RemoteUnrealParam value" tells you `arg[1]:get()` is needed. Always log the verbatim error inside `pcall` and read the wording — UE4SS's marshaler errors are uncommonly specific. The cost of *not* reading them carefully is multiple game-restart iterations on shapes that the error message already ruled out.

2. **C++-flavored intuition for UE Lua is a high-cost reflex.** Three iterations were burned on this UFunction because the C++ signature *says* `(bool& OutValid, FString& OutId)` and that mental model carried over silently. UE4SS Lua does not work that way at all; tables are the only by-ref bridge. When approaching any UFunction call shape question, the discipline is: *(a) find a working call elsewhere in OSPlus / referenced mods and copy its shape, (b) only if no precedent exists, consult upstream issues filtered to the exact UE4SS version we ship.* Reading a UFunction's C++ signature and "translating" it to Lua is a category error. See `.cursor/rules/lua-conventions.mdc` "Lua-not-C++ reflex" for the full anti-pattern catalog.

3. **Anchor every UE4SS lookup to your shipping version.** UE4SS's Lua marshaling layer changed materially between 3.0 and 3.1. A v33 attempt was framed around an Issue #920 thread that turned out to describe a 3.1 fix; on 3.0.1 the relevant convention is the more conservative `({}, {})` shape with multi-param collapse per #971. **Quoting newer-version threads as if their fixes apply to us is the single highest-cost mistake in this codebase's history.** AGENTS.md "Engine constraints" section pins the version explicitly for this reason; when in doubt, read it again.

## Related

- **Code (production reference):** `mod/OSPlus/scripts/identity.lua` → `readAuthenticatedPlayerId` + `pluckOutParam` + `toLuaString`. Live, validated, copy-paste-friendly.
- **Supersedes (partially):** `docs/learnings/ue4ss-outparam-marshaling-failure.md` — its "no Lua-side fix exists for `(Bool out, X out)` UFunctions on UE4SS 3.0.1" conclusion is refuted at the call-shape layer (the `({}, {})` shape works). Its claims about specific `PMPlayerModel.GetCached*V1` UFunctions remain *untested* with the new shape — those calls may also work now but haven't been re-probed; the old learning is annotated with the corrected coverage banner.
- **ADR consuming this finding:** `docs/decisions/0001-identity-model.md` — Stage 5 production-validated post-v35; the R-B substrate is now end-to-end-verified against the running game.
- **Rule references:**
  - `.cursor/rules/lua-conventions.mdc` → "UE4SS build" (version pinning) + "Lua-not-C++ reflex" (the anti-pattern catalog).
- **KB references:** `KNOWLEDGEBASE.md` → *UE4SS Lua API* + *Player Identity Reference* (Lua-side reachability subsection).
- **Upstream UE4SS issues** (filter to 3.0.1 / pre-3.1 reports when reading):
  - [#920 — UFunction out-param marshaling convention](https://github.com/UE4SS-RE/RE-UE4SS/issues/920)
  - [#971 — multi-out-param collapse in 3.0.x](https://github.com/UE4SS-RE/RE-UE4SS/issues/971)
  - [#368 — historical context for table-as-by-ref pattern](https://github.com/UE4SS-RE/RE-UE4SS/issues/368)
- **Failure-mode docs in the lineage:** the v33→v34→v35 evolution is preserved as comments in `identity.lua` `readAuthenticatedPlayerId` for a reason — when the next agent reads the production code and wonders "why both buckets if only one gets populated?", the comment chain explains. Don't strip that.
