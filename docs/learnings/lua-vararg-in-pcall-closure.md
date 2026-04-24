# lua-vararg-in-pcall-closure

| Field | Value |
|---|---|
| Date | 2026-04-21 |
| Area | mod |
| Tags | lua, ue4ss, pcall, vararg, startup-crash, syntax-error |
| Status | confirmed |

## Symptom

The mod failed during startup before any gameplay code ran, with UE4SS reporting:

```text
error loading module 'native_emotes' ... cannot use '...' outside a vararg function near '...'
```

Because this happens while `require("native_emotes")` is loading, the whole mod fails to boot and `main.lua` never runs.

## Root cause

`tryMethodVariant` used `...` inside an inner anonymous function passed to `pcall`.

In Lua, the outer function may be vararg, but the nested closure is not automatically vararg. Referencing `...` inside that inner function is therefore a parse-time syntax error, not a runtime exception.

Bad pattern:

```lua
local function f(...)
    return pcall(function()
        return g(...)
    end)
end
```

## Fix

Capture the varargs into locals before entering the nested closure, then unpack those locals inside `pcall`:

```lua
local args = { ... }
local argCount = select("#", ...)

local ok, result = pcall(function()
    return target.obj[methodName](target.obj, table.unpack(args, 1, argCount))
end)
```

See `mod/OSPlus/scripts/native_emotes.lua` `tryMethodVariant()`.

## Lesson

When wrapping UE calls in `pcall`, never forward `...` directly from an outer function into the nested closure. Capture varargs first, then unpack from locals. Otherwise the failure mode is a full mod startup crash, not a normal logged runtime error.

## Related

- Files: `mod/OSPlus/scripts/native_emotes.lua`, `.cursor/rules/lua-conventions.mdc`
- Prior learnings (if this supersedes or extends one): none
- Upstream sources / docs / discussions, if any: Lua vararg scoping rules observed in the UE4SS runtime used by OSPlus